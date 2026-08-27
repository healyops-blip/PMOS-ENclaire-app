"""Streaming validation and path-safe private storage for medical files."""

from __future__ import annotations

import hashlib
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from fastapi import UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from pypdf import PdfReader

from pomi_backend.api.business import BusinessError

MAX_FILE_SIZE = 20 * 1024 * 1024
MAX_PIXEL_COUNT = 25_000_000
_EXTENSIONS = {"image/jpeg": ".jpg", "image/png": ".png", "application/pdf": ".pdf"}


@dataclass(frozen=True, slots=True)
class StoredFile:
    path: Path
    relative_path: str
    mime_type: str
    size: int
    sha256: str
    pixel_count: int | None
    page_count: int


def safe_file_name(value: str | None) -> str:
    # Treat both POSIX and Windows separators as untrusted, regardless of host OS.
    name = Path((value or "upload").replace("\\", "/")).name
    name = re.sub(r"[\x00-\x1f\x7f]", "", name).strip()
    return (name or "upload")[:255]


def _inspect_and_normalize(path: Path) -> tuple[str, int | None, int]:
    with path.open("rb") as source:
        signature = source.read(5)
    if signature == b"%PDF-":
        try:
            pages = len(PdfReader(path).pages)
        except Exception as exc:
            raise BusinessError("UNSUPPORTED_FORMAT", "The PDF file is invalid.", 415) from exc
        if pages != 1:
            raise BusinessError("MULTI_PAGE_PDF", "Only single-page PDFs are supported.", 415)
        return "application/pdf", None, pages
    try:
        with Image.open(path) as image:
            image_format = image.format
            pixels = image.width * image.height
            if pixels > MAX_PIXEL_COUNT:
                raise BusinessError("IMAGE_TOO_LARGE", "The image exceeds 25 megapixels.", 413)
            image.verify()
        if image_format not in {"JPEG", "PNG"}:
            raise BusinessError("UNSUPPORTED_FORMAT", "Use JPEG, PNG, or PDF.", 415)
        with Image.open(path) as image:
            orientation = image.getexif().get(274, 1)
        if orientation not in {None, 1}:
            with Image.open(path) as image:
                normalized = ImageOps.exif_transpose(image)
                normalized.save(path, format=image_format)
        return "image/jpeg" if image_format == "JPEG" else "image/png", pixels, 1
    except BusinessError:
        raise
    except Image.DecompressionBombError as exc:
        raise BusinessError("IMAGE_TOO_LARGE", "The image exceeds 25 megapixels.", 413) from exc
    except (UnidentifiedImageError, OSError) as exc:
        raise BusinessError("UNSUPPORTED_FORMAT", "The image file is invalid.", 415) from exc


def store_upload(
    upload: UploadFile,
    *,
    storage_root: Path,
    document_id: str,
    revision_id: str,
) -> StoredFile:
    temporary_root = storage_root / ".tmp"
    temporary_root.mkdir(parents=True, exist_ok=True)
    temporary = temporary_root / f"{uuid4().hex}.upload"
    size = 0
    try:
        with temporary.open("wb") as destination:
            while chunk := upload.file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_FILE_SIZE:
                    raise BusinessError("FILE_TOO_LARGE", "The file exceeds 20 MiB.", 413)
                destination.write(chunk)
        if size == 0:
            raise BusinessError("UNSUPPORTED_FORMAT", "The file is empty.", 415)
        mime_type, pixels, pages = _inspect_and_normalize(temporary)
        size = temporary.stat().st_size
        if size > MAX_FILE_SIZE:
            raise BusinessError("FILE_TOO_LARGE", "The normalized file exceeds 20 MiB.", 413)
        hasher = hashlib.sha256()
        with temporary.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                hasher.update(chunk)
        digest = hasher.hexdigest()
        relative = Path("documents") / document_id / f"{revision_id}{_EXTENSIONS[mime_type]}"
        final_path = storage_root / relative
        final_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(temporary), str(final_path))
        return StoredFile(
            path=final_path,
            relative_path=relative.as_posix(),
            mime_type=mime_type,
            size=size,
            sha256=digest,
            pixel_count=pixels,
            page_count=pages,
        )
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def private_path(storage_root: Path, relative_path: str) -> Path:
    root = storage_root.resolve()
    path = (root / relative_path).resolve()
    if root not in path.parents or not path.is_file():
        raise BusinessError("RESOURCE_NOT_FOUND", "The private file was not found.", 404)
    return path
