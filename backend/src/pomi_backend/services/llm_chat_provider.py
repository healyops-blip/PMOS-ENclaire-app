"""Generic Chat LLM provider using OpenAI-compatible /chat/completions."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

import httpx


@dataclass(frozen=True, slots=True)
class ChatRequest:
    model: str
    messages: list[dict[str, Any]]
    response_format: dict[str, Any] | None = None
    temperature: float = 0.2
    top_p: float = 0.9
    presence_penalty: float = 0.0
    frequency_penalty: float = 0.0


@dataclass(frozen=True, slots=True)
class ChatResponse:
    raw_response: dict[str, Any]
    content: str


class ChatProviderError(Exception):
    def __init__(self, code: str, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.code = code
        self.retryable = retryable


class QwenChatProvider:
    """Qwen text chat adapter; credentials kept in process memory only."""

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

    def chat(self, request: ChatRequest) -> ChatResponse:
        if not self.api_key:
            raise ChatProviderError("LLM_NOT_CONFIGURED", "LLM service is not configured.", retryable=False)
        body = {
            "model": request.model or self.model,
            "messages": request.messages,
            "temperature": request.temperature,
            "top_p": request.top_p,
            "presence_penalty": request.presence_penalty,
            "frequency_penalty": request.frequency_penalty,
        }
        if request.response_format:
            body["response_format"] = request.response_format
        try:
            active_client = self.client or httpx.Client(timeout=self.timeout_seconds)
            response = active_client.post(
                f"{self.api_base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                content=json.dumps(body, ensure_ascii=False),
            )
            response.raise_for_status()
            raw = response.json()
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code if exc.response is not None else None
            msg = exc.response.text if exc.response is not None else str(exc)
            raise ChatProviderError(
                "HTTP_ERROR",
                f"LLM HTTP {status}: {msg[:200]}",
                retryable=500 <= (status or 500) < 600,
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise ChatProviderError("NETWORK_OR_JSON", "LLM network or JSON error.", retryable=True) from exc
        finally:
            if self.client is None and "active_client" in locals():
                active_client.close()
        try:
            content = raw["choices"][0]["message"]["content"]
            if isinstance(content, str) and content.startswith("```"):
                content = content.strip("`")
                if content.startswith("json"):
                    content = content[4:].lstrip()
            if not isinstance(content, str):
                raise TypeError("message content is not a string")
        except (KeyError, TypeError, IndexError) as exc:
            raise ChatProviderError("RESPONSE_FORMAT", "LLM response format is invalid.", retryable=True) from exc
        return ChatResponse(raw_response=raw, content=content)
