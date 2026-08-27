"""Validated private storage for medical-document uploads."""

from __future__ import annotations

import hashlib
import shutil
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from fastapi import UploadFile
from PIL import Image, UnidentifiedImageError
from pypdf import PdfReader

from pomi_backend.api.business import BusinessError

MAX_FILE_SIZE = 20 * 1024 * 1024
MAX_PIXEL_COUNT = 25_000_000
ALLOWED_MIME_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "application/pdf": ".pdf",
}


@dataclass(frozen=True, slots=True)
class StoredUpload:
    path: Path
    relative_path: str
    sha256: str
    size: int
    mime_type: str
    pixel_count: int | None
    page_count: int


def _inspect_file(path: Path, mime_type: str) -> tuple[int | None, int]:
    if mime_type == "application/pdf":
        try:
            page_count = len(PdfReader(path).pages)
        except Exception as exc:
            raise BusinessError("UNSUPPORTED_FORMAT", "The PDF file is invalid.", 415) from exc
        if page_count != 1:
            raise BusinessError("MULTI_PAGE_PDF", "Only single-page PDFs are supported.", 415)
        return None, page_count
    try:
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            pixel_count = image.width * image.height
    except (UnidentifiedImageError, OSError) as exc:
        raise BusinessError("UNSUPPORTED_FORMAT", "The image file is invalid.", 415) from exc
    if pixel_count > MAX_PIXEL_COUNT:
        raise BusinessError("IMAGE_TOO_LARGE", "The image exceeds 25 megapixels.", 413)
    return pixel_count, 1


def store_upload(
    upload: UploadFile,
    *,
    storage_root: Path,
    document_id: str,
    revision_id: str,
) -> StoredUpload:
    mime_type = (upload.content_type or "").lower()
    extension = ALLOWED_MIME_TYPES.get(mime_type)
    if extension is None:
        raise BusinessError("UNSUPPORTED_FORMAT", "Use JPEG, PNG, or a single-page PDF.", 415)
    temp_root = storage_root / ".tmp"
    temp_root.mkdir(parents=True, exist_ok=True)
    temp_path = temp_root / f"{uuid4().hex}.upload"
    hasher = hashlib.sha256()
    size = 0
    try:
        with temp_path.open("wb") as destination:
            while chunk := upload.file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_FILE_SIZE:
                    raise BusinessError("FILE_TOO_LARGE", "The file exceeds 20 MiB.", 413)
                hasher.update(chunk)
                destination.write(chunk)
        if size == 0:
            raise BusinessError("UNSUPPORTED_FORMAT", "The file is empty.", 415)
        pixel_count, page_count = _inspect_file(temp_path, mime_type)
        relative_path = Path("documents") / document_id / f"{revision_id}{extension}"
        final_path = storage_root / relative_path
        final_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(temp_path), str(final_path))
        return StoredUpload(
            path=final_path,
            relative_path=relative_path.as_posix(),
            sha256=hasher.hexdigest(),
            size=size,
            mime_type=mime_type,
            pixel_count=pixel_count,
            page_count=page_count,
        )
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def private_path(storage_root: Path, relative_path: str) -> Path:
    root = storage_root.resolve()
    path = (root / relative_path).resolve()
    if root not in path.parents:
        raise BusinessError("FORBIDDEN_RESOURCE", "Invalid private file path.", 403)
    if not path.is_file():
        raise BusinessError("RESOURCE_NOT_FOUND", "The private file is missing.", 404)
    return path
