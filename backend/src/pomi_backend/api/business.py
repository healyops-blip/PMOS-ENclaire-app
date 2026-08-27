"""Shared response and error helpers for authenticated business APIs."""

from __future__ import annotations

from typing import Any

from fastapi import Request


class BusinessError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        status_code: int,
        *,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}


def success(request: Request, data: Any) -> dict[str, Any]:
    return {
        "success": True,
        "data": data,
        "request_id": request.state.request_id,
        "error": None,
    }


def business_error_content(request: Request, error: BusinessError) -> dict[str, Any]:
    return {
        "success": False,
        "data": None,
        "request_id": request.state.request_id,
        "error": {
            "code": error.code,
            "message": error.message,
            "retryable": False,
            "retry_after_seconds": None,
            "details": error.details,
        },
    }
