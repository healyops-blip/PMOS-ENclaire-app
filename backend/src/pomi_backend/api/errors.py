"""Stable public error responses for authentication APIs."""

from __future__ import annotations

from fastapi import Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from pomi_backend.api.business import BusinessError, business_error_content
from pomi_backend.services.auth import AuthError
from pomi_backend.services.rate_limit import RateLimitExceeded


def error_content(code: str, message: str) -> dict[str, dict[str, str]]:
    return {"error": {"code": code, "message": message}}


async def auth_error_handler(request: Request, error: AuthError) -> JSONResponse:
    headers = {"WWW-Authenticate": "Bearer"} if error.status_code == 401 else None
    if not request.url.path.startswith("/api/auth/"):
        return JSONResponse(
            status_code=error.status_code,
            content=business_error_content(
                request,
                BusinessError(
                    "AUTHENTICATION_REQUIRED", "Authentication is required.", error.status_code
                ),
            ),
            headers=headers,
        )
    return JSONResponse(
        status_code=error.status_code,
        content=error_content(error.code, error.message),
        headers=headers,
    )


async def rate_limit_error_handler(_: Request, error: RateLimitExceeded) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content=error_content(
            "AUTH_RATE_LIMITED", "Too many authentication attempts. Try again later."
        ),
        headers={"Retry-After": str(error.retry_after_seconds)},
    )


async def validation_error_handler(request: Request, __: RequestValidationError) -> JSONResponse:
    if not request.url.path.startswith("/api/auth/"):
        return JSONResponse(
            status_code=422,
            content=business_error_content(
                request,
                BusinessError("VALIDATION_ERROR", "The request contains invalid fields.", 422),
            ),
        )
    return JSONResponse(
        status_code=422,
        content=error_content("VALIDATION_ERROR", "The request contains invalid fields."),
    )


async def business_error_handler(request: Request, error: BusinessError) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content=business_error_content(request, error),
    )
