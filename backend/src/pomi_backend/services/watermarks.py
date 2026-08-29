"""Private, deterministic POMI display derivatives generated after OCR."""

from __future__ import annotations

import hashlib
import logging
from pathlib import Path
from uuid import uuid4

from PIL import Image, ImageOps
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
WATERMARK_VERSION = "pomi-watermark-v2"
_WATERMARK_OPACITY = 0.17
_WATERMARK_WIDTH_RATIO = 0.34
_WATERMARK_HEIGHT_LIMIT = 0.72
_WATERMARK_PATH = Path(__file__).resolve().parents[1] / "assets" / "PomiWatermarkV2.png"


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
    with Image.open(_WATERMARK_PATH) as opened:
        watermark = opened.convert("RGBA")
    scale = min(
        width * _WATERMARK_WIDTH_RATIO / watermark.width,
        height * _WATERMARK_HEIGHT_LIMIT / watermark.height,
    )
    watermark = watermark.resize(
        (
            max(1, round(watermark.width * scale)),
            max(1, round(watermark.height * scale)),
        ),
        Image.Resampling.LANCZOS,
    )
    watermark.putalpha(
        watermark.getchannel("A").point(lambda alpha: round(alpha * _WATERMARK_OPACITY))
    )
    overlay = Image.new("RGBA", image.size, (255, 255, 255, 0))
    overlay.alpha_composite(
        watermark,
        (
            (width - watermark.width) // 2,
            (height - watermark.height) // 2,
        ),
    )
    rendered = Image.alpha_composite(image, overlay)
    if mime_type == "image/jpeg":
        rendered.convert("RGB").save(destination, format="JPEG", quality=90, optimize=True)
    else:
        rendered.save(destination, format="PNG", optimize=True)
    return width, height


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()
