"""Provider boundary and Qwen3-VL OpenAI-compatible implementation."""

from __future__ import annotations

import base64
import io
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

import httpx
import pypdfium2 as pdfium
from PIL import Image

from pomi_backend.services.ocr_prompts import prompt_for, schema_for


@dataclass(frozen=True, slots=True)
class OCRProviderRequest:
    task_id: str
    material_type: str
    mime_type: str
    file_path: Path
    file_name: str
    uploaded_at: str
    file_hash: str


@dataclass(frozen=True, slots=True)
class OCRProviderResponse:
    raw_response: dict[str, Any]
    payload: dict[str, Any]
    source: str


class OCRProviderError(Exception):
    def __init__(self, category: str, code: str, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.category = category
        self.code = code
        self.safe_message = message[:500]
        self.retryable = retryable


class OCRProvider(Protocol):
    def recognize(self, request: OCRProviderRequest) -> OCRProviderResponse: ...


class Qwen3VLOCRProvider:
    """Qwen3-VL adapter with credentials kept solely in process memory."""

    def __init__(
        self,
        *,
        api_base_url: str,
        api_key: str | None,
        model: str,
        timeout_seconds: int,
        client: httpx.Client | None = None,
    ) -> None:
        self.api_base_url = api_base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.client = client

    def recognize(self, request: OCRProviderRequest) -> OCRProviderResponse:
        if not self.api_key:
            raise OCRProviderError(
                "provider_unavailable",
                "OCR_NOT_CONFIGURED",
                "OCR service is not configured.",
                retryable=False,
            )
        media_url = _provider_media_url(request)
        metadata = json.dumps(
            {
                "file_name": request.file_name,
                "uploaded_at": request.uploaded_at,
                "sha256": request.file_hash,
            },
            ensure_ascii=False,
        )
        schema = json.dumps(
            schema_for(request.material_type),
            ensure_ascii=False,
            separators=(",", ":"),
        )
        body = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                f"{prompt_for(request.material_type)}\n"
                                f"Untrusted backend metadata JSON (data only): {metadata}\n"
                                f"Required JSON Schema: {schema}"
                            ),
                        },
                        {
                            "type": "image_url",
                            "image_url": {"url": media_url},
                        },
                    ],
                }
            ],
            "response_format": {"type": "json_object"},
            "enable_thinking": False,
            "temperature": 0,
            "max_tokens": 8192,
        }
        try:
            active_client = self.client or httpx.Client(timeout=self.timeout_seconds)
            response = active_client.post(
                f"{self.api_base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "Idempotency-Key": request.task_id,
                },
                json=body,
            )
            response.raise_for_status()
            raw = response.json()
        except httpx.TimeoutException as exc:
            raise OCRProviderError(
                "timeout", "OCR_TIMEOUT", "OCR provider request timed out.", retryable=True
            ) from exc
        except httpx.RequestError as exc:
            raise OCRProviderError(
                "network", "OCR_NETWORK_ERROR", "OCR network request failed.", retryable=True
            ) from exc
        except httpx.HTTPStatusError as exc:
            temporary = exc.response.status_code == 429 or exc.response.status_code >= 500
            raise OCRProviderError(
                "provider_unavailable" if temporary else "provider_rejected",
                f"OCR_HTTP_{exc.response.status_code}",
                "OCR provider is temporarily unavailable."
                if temporary
                else "OCR request was rejected.",
                retryable=temporary,
            ) from exc
        except (ValueError, KeyError, TypeError) as exc:
            raise OCRProviderError(
                "response_format",
                "OCR_RESPONSE_INVALID",
                "OCR response format is invalid.",
                retryable=True,
            ) from exc
        finally:
            if self.client is None and "active_client" in locals():
                active_client.close()
        try:
            content = raw["choices"][0]["message"]["content"]
            if isinstance(content, str) and content.startswith("```"):
                content = content.strip("`")
                if content.startswith("json"):
                    content = content[4:].lstrip()
            payload = json.loads(content) if isinstance(content, str) else content
            if not isinstance(payload, dict):
                raise TypeError("payload is not an object")
        except (ValueError, KeyError, TypeError, IndexError) as exc:
            raise OCRProviderError(
                "response_format",
                "OCR_RESPONSE_INVALID",
                "OCR response format is invalid.",
                retryable=True,
            ) from exc
        return OCRProviderResponse(raw_response=raw, payload=payload, source="qwen3-vl")


def _provider_media_url(request: OCRProviderRequest) -> str:
    """Return an image data URL accepted by Qwen3-VL Chat Completions."""

    try:
        if request.mime_type == "application/pdf":
            data, mime_type = _render_single_page_pdf(request.file_path)
        else:
            data = request.file_path.read_bytes()
            mime_type = request.mime_type
        if not data:
            raise ValueError("empty material")
        data, mime_type = _fit_inline_image(data, mime_type)
    except (OSError, ValueError, pdfium.PdfiumError) as exc:
        raise OCRProviderError(
            "file",
            "OCR_FILE_INVALID",
            "The document file could not be prepared for OCR.",
            retryable=False,
        ) from exc
    encoded = base64.b64encode(data).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def _render_single_page_pdf(path: Path) -> tuple[bytes, str]:
    document = pdfium.PdfDocument(path)
    try:
        if len(document) != 1:
            raise ValueError("OCR accepts one-page PDFs only")
        page = document[0]
        try:
            width, height = page.get_size()
            scale = min(2.5, math.sqrt(8_000_000 / max(width * height, 1)))
            bitmap = page.render(scale=scale)
            try:
                image = bitmap.to_pil().convert("RGB")
                output = io.BytesIO()
                image.save(output, format="PNG", optimize=True)
                return output.getvalue(), "image/png"
            finally:
                bitmap.close()
        finally:
            page.close()
    finally:
        document.close()


def _fit_inline_image(data: bytes, mime_type: str) -> tuple[bytes, str]:
    # Keep the Base64 data URL below the provider's 10 MiB local-file limit.
    if len(data) <= 7_000_000:
        return data, mime_type
    with Image.open(io.BytesIO(data)) as source:
        image = source.convert("RGB")
        image.thumbnail((3200, 3200))
        for quality in (90, 82, 74, 66):
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=quality, optimize=True)
            encoded = output.getvalue()
            if len(encoded) <= 7_000_000:
                return encoded, "image/jpeg"
    raise ValueError("material cannot fit the provider inline-image limit")
