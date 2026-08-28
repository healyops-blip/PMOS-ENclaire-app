"""Private, deterministic POMI display derivatives generated after OCR."""

from __future__ import annotations

import hashlib
import logging
from pathlib import Path
from uuid import uuid4

from PIL import Image, ImageDraw, ImageFont, ImageOps
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    Document,
    DocumentDisplayAsset,
    DocumentRevision,
    OCRTask,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.services.document_storage import private_path

logger = logging.getLogger("pomi.document.watermark")

ASSET_TYPE = "pomi_watermarked_display"
WATERMARK_VERSION = "pomi-watermark-v1"
_WATERMARK_OPACITY = 56
_WATERMARK_SHADOW = (105, 78, 153, 48)
_FONT_PATH = Path(__file__).resolve().parents[1] / "assets" / "PomiWatermarkSubset.ttf"


def display_asset_data(asset: DocumentDisplayAsset | None) -> dict | None:
    if asset is None:
        return None
    endpoint = (
        f"/api/documents/{asset.document_id}/revisions/{asset.document_revision_id}/display/file"
    )
    return {
        "id": asset.id,
        "document_id": asset.document_id,
        "document_revision_id": asset.document_revision_id,
        "asset_type": asset.asset_type,
        "watermark_version": asset.watermark_version,
        "status": asset.status,
        "mime_type": asset.mime_type,
        "file_size_bytes": asset.file_size_bytes,
        "file_hash": asset.file_hash,
        "pixel_width": asset.pixel_width,
        "pixel_height": asset.pixel_height,
        "attempt_count": asset.attempt_count,
        "generated_at": asset.generated_at.isoformat() if asset.generated_at else None,
        "error": (
            {"code": asset.failure_code, "message": asset.failure_message}
            if asset.failure_code
            else None
        ),
        "file_endpoint": endpoint if asset.status == "ready" else None,
    }


class DocumentWatermarkService:
    def __init__(self, session: Session, storage_root: Path) -> None:
        self.session = session
        self.storage_root = storage_root

    def get(self, document_id: str, revision_id: str) -> DocumentDisplayAsset | None:
        return self.session.scalar(
            select(DocumentDisplayAsset).where(
                DocumentDisplayAsset.document_id == document_id,
                DocumentDisplayAsset.document_revision_id == revision_id,
                DocumentDisplayAsset.asset_type == ASSET_TYPE,
                DocumentDisplayAsset.watermark_version == WATERMARK_VERSION,
            )
        )

    def generate(
        self,
        document: Document,
        revision: DocumentRevision,
        *,
        force: bool = False,
        require_ocr_success: bool = True,
    ) -> DocumentDisplayAsset:
        if document.id != revision.document_id:
            raise ValueError("document revision does not belong to document")
        if require_ocr_success and not self._has_successful_ocr(document.id, revision.id):
            raise BusinessError(
                "WATERMARK_OCR_NOT_READY",
                "The source revision has not completed OCR.",
                409,
            )

        asset = self._get_or_create(document, revision)
        if revision.mime_type not in {"image/jpeg", "image/png"}:
            asset.status = "unsupported"
            asset.failure_code = "WATERMARK_FORMAT_UNSUPPORTED"
            asset.failure_message = "Watermarked display is available for JPEG and PNG images."
            asset.updated_at = utc_now()
            self.session.commit()
            self.session.refresh(asset)
            return asset

        if asset.status == "ready" and not force and asset.storage_path:
            try:
                private_path(self.storage_root, asset.storage_path)
                return asset
            except BusinessError:
                pass

        asset.status = "processing"
        asset.attempt_count += 1
        asset.failure_code = None
        asset.failure_message = None
        asset.updated_at = utc_now()
        self.session.commit()

        temporary: Path | None = None
        try:
            source = private_path(self.storage_root, revision.storage_path)
            extension = ".jpg" if revision.mime_type == "image/jpeg" else ".png"
            relative = (
                Path("derivatives") / document.id / revision.id / f"{WATERMARK_VERSION}{extension}"
            )
            destination = self.storage_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary_root = self.storage_root / ".tmp"
            temporary_root.mkdir(parents=True, exist_ok=True)
            temporary = temporary_root / f"{uuid4().hex}.watermark{extension}"
            width, height = _render_watermarked_image(
                source,
                temporary,
                mime_type=revision.mime_type,
            )
            temporary.replace(destination)
            size = destination.stat().st_size
            digest = _sha256(destination)
            asset.status = "ready"
            asset.storage_path = relative.as_posix()
            asset.file_hash = digest
            asset.file_size_bytes = size
            asset.mime_type = revision.mime_type
            asset.pixel_width = width
            asset.pixel_height = height
            asset.failure_code = None
            asset.failure_message = None
            asset.generated_at = utc_now()
            asset.updated_at = asset.generated_at
            self.session.commit()
            self.session.refresh(asset)
            return asset
        except Exception:
            logger.exception(
                "document_id=%s revision_id=%s status=watermark_failed",
                document.id,
                revision.id,
            )
            self.session.rollback()
            asset = self.get(document.id, revision.id) or asset
            asset.status = "failed"
            asset.storage_path = None
            asset.file_hash = None
            asset.file_size_bytes = None
            asset.mime_type = None
            asset.pixel_width = None
            asset.pixel_height = None
            asset.failure_code = "WATERMARK_RENDER_FAILED"
            asset.failure_message = "The watermarked display image could not be generated."
            asset.generated_at = None
            asset.updated_at = utc_now()
            self.session.commit()
            self.session.refresh(asset)
            return asset
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

    def file(self, asset: DocumentDisplayAsset) -> Path:
        if asset.status != "ready" or not asset.storage_path:
            raise BusinessError(
                "WATERMARK_NOT_READY",
                "The watermarked display image is not ready.",
                409,
            )
        return private_path(self.storage_root, asset.storage_path)

    def _has_successful_ocr(self, document_id: str, revision_id: str) -> bool:
        return (
            self.session.scalar(
                select(OCRTask.id)
                .where(
                    OCRTask.document_id == document_id,
                    OCRTask.document_revision_id == revision_id,
                    OCRTask.status.in_(("pending_confirmation", "confirmed")),
                )
                .limit(1)
            )
            is not None
        )

    def _get_or_create(
        self,
        document: Document,
        revision: DocumentRevision,
    ) -> DocumentDisplayAsset:
        asset = self.get(document.id, revision.id)
        if asset is not None:
            return asset
        asset = DocumentDisplayAsset(
            id=new_uuid(),
            document_id=document.id,
            document_revision_id=revision.id,
            asset_type=ASSET_TYPE,
            watermark_version=WATERMARK_VERSION,
            status="processing",
        )
        self.session.add(asset)
        try:
            self.session.commit()
            self.session.refresh(asset)
            return asset
        except IntegrityError:
            self.session.rollback()
            existing = self.get(document.id, revision.id)
            if existing is None:
                raise
            return existing


def generate_watermark_after_ocr(
    session: Session,
    storage_root: Path,
    document: Document,
    revision: DocumentRevision,
) -> DocumentDisplayAsset | None:
    """Best-effort hook: watermark failures must never change OCR success."""

    try:
        return DocumentWatermarkService(session, storage_root).generate(document, revision)
    except Exception:
        session.rollback()
        logger.exception(
            "document_id=%s revision_id=%s status=watermark_hook_failed",
            document.id,
            revision.id,
        )
        return None


def _render_watermarked_image(
    source: Path,
    destination: Path,
    *,
    mime_type: str,
) -> tuple[int, int]:
    with Image.open(source) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGBA")
    width, height = image.size
    overlay = Image.new("RGBA", image.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(overlay)
    mark_width, mark_height = _draw_pomi_mark(draw, width, height)

    font_size = max(1, round(mark_width * 0.20))
    tagline_size = max(1, round(mark_width * 0.075))
    brand_font = ImageFont.truetype(_FONT_PATH, font_size)
    tagline_font = ImageFont.truetype(_FONT_PATH, tagline_size)
    mark_top = (height - mark_height) / 2 - mark_height * 0.10
    mark_bottom = mark_top + mark_height
    brand_y = mark_bottom + max(1, mark_width * 0.025)
    draw.text(
        (width / 2 + max(1, mark_width * 0.012), brand_y + max(1, mark_width * 0.012)),
        "POMI",
        font=brand_font,
        anchor="ma",
        fill=_WATERMARK_SHADOW,
    )
    draw.text(
        (width / 2, brand_y),
        "POMI",
        font=brand_font,
        anchor="ma",
        fill=(255, 255, 255, _WATERMARK_OPACITY),
    )
    tagline_y = brand_y + font_size * 1.15
    draw.text(
        (width / 2 + max(1, mark_width * 0.009), tagline_y + max(1, mark_width * 0.009)),
        "由 POMI 识别整理",
        font=tagline_font,
        anchor="ma",
        fill=_WATERMARK_SHADOW,
    )
    draw.text(
        (width / 2, tagline_y),
        "由 POMI 识别整理",
        font=tagline_font,
        anchor="ma",
        fill=(255, 255, 255, _WATERMARK_OPACITY),
    )
    rendered = Image.alpha_composite(image, overlay)
    if mime_type == "image/jpeg":
        rendered.convert("RGB").save(destination, format="JPEG", quality=90, optimize=True)
    else:
        rendered.save(destination, format="PNG", optimize=True)
    return width, height


def _draw_pomi_mark(draw: ImageDraw.ImageDraw, width: int, height: int) -> tuple[float, float]:
    natural_width = 453.0
    natural_height = 604.0
    scale = min(width * 0.45 / natural_width, height * 0.50 / natural_height)
    mark_width = natural_width * scale
    mark_height = natural_height * scale
    left = (width - mark_width) / 2
    top = (height - mark_height) / 2 - mark_height * 0.10

    def point(
        value: tuple[float, float],
        offset: float = 0,
    ) -> tuple[float, float]:
        return (
            left + (value[0] - 409) * scale + offset,
            top + (value[1] - 256) * scale + offset,
        )

    def polygon(values: list[tuple[float, float]]) -> None:
        shadow_offset = max(1, mark_width * 0.012)
        draw.polygon(
            [point(value, shadow_offset) for value in values],
            fill=_WATERMARK_SHADOW,
        )
        draw.polygon(
            [point(value) for value in values],
            fill=(255, 255, 255, _WATERMARK_OPACITY),
        )

    main = [(409.0, 860.0), (409.0, 483.0)]
    _cubic(main, (409, 355), (509, 256), (636, 256))
    _cubic(main, (762, 256), (862, 355), (862, 483))
    _cubic(main, (862, 617), (765, 722), (638, 722))
    main.append((572, 722))
    _cubic(main, (586, 672), (620, 627), (673, 597))
    _cubic(main, (743, 558), (789, 532), (804, 474))
    _cubic(main, (810, 452), (805, 444), (790, 440))
    _cubic(main, (772, 436), (763, 431), (756, 416))
    _cubic(main, (735, 380), (691, 365), (644, 365))
    _cubic(main, (567, 365), (510, 416), (510, 490))
    main.extend(((510, 802), (444, 860)))
    polygon(main)

    ear = [(570.0, 462.0)]
    _cubic(ear, (575, 445), (592, 438), (606, 444))
    _cubic(ear, (612, 447), (617, 452), (620, 457))
    ear.append((587, 493))
    _cubic(ear, (577, 483), (567, 473), (570, 462))
    polygon(ear)

    eye = [(688.0, 456.0)]
    _cubic(eye, (688, 440), (698, 431), (713, 431))
    _cubic(eye, (730, 431), (739, 442), (739, 458))
    _cubic(eye, (739, 465), (735, 471), (737, 477))
    _cubic(eye, (733, 483), (724, 485), (716, 483))
    _cubic(eye, (699, 483), (688, 473), (688, 456))
    polygon(eye)
    return mark_width, mark_height


def _cubic(
    points: list[tuple[float, float]],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
) -> None:
    start = points[-1]
    for index in range(1, 17):
        t = index / 16
        inverse = 1 - t
        points.append(
            (
                inverse**3 * start[0]
                + 3 * inverse**2 * t * control_a[0]
                + 3 * inverse * t**2 * control_b[0]
                + t**3 * end[0],
                inverse**3 * start[1]
                + 3 * inverse**2 * t * control_a[1]
                + 3 * inverse * t**2 * control_b[1]
                + t**3 * end[1],
            )
        )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()
