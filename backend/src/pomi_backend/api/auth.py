"""Registration, login, and current-account routes."""

from __future__ import annotations

from fastapi import APIRouter, Request, status

from pomi_backend.api.dependencies import (
    AuthServiceDependency,
    CurrentAccount,
    SessionId,
)
from pomi_backend.db.models import UserAccount
from pomi_backend.schemas.auth import (
    AccountResponse,
    ErrorResponse,
    LoginRequest,
    LoginResponse,
    RegisterRequest,
)

router = APIRouter(prefix="/api/auth", tags=["authentication"])


def account_response(account: UserAccount) -> AccountResponse:
    return AccountResponse(
        uid=account.uid,
        account_name=account.account_name,
        account_type=account.account_type,
        onboarding_completed=account.onboarding_completed,
        status=account.status,
        phone_number=account.phone_number,
        phone_verified=account.phone_verified_at is not None,
    )


def apply_auth_rate_limit(request: Request, action: str) -> None:
    client_host = request.client.host if request.client is not None else "unknown"
    request.app.state.auth_rate_limiter.hit(f"{action}:{client_host}")


@router.post(
    "/register",
    response_model=AccountResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        status.HTTP_409_CONFLICT: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
        status.HTTP_429_TOO_MANY_REQUESTS: {"model": ErrorResponse},
    },
)
def register(
    payload: RegisterRequest,
    request: Request,
    service: AuthServiceDependency,
) -> AccountResponse:
    apply_auth_rate_limit(request, "register")
    account = service.register(
        account_name=payload.account_name,
        password=payload.password.get_secret_value(),
        phone_number=payload.phone_number,
    )
    return account_response(account)


@router.post(
    "/login",
    response_model=LoginResponse,
    responses={
        status.HTTP_401_UNAUTHORIZED: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
        status.HTTP_429_TOO_MANY_REQUESTS: {"model": ErrorResponse},
    },
)
def login(
    payload: LoginRequest,
    request: Request,
    service: AuthServiceDependency,
) -> LoginResponse:
    apply_auth_rate_limit(request, "login")
    result = service.login(
        account_name=payload.account_name,
        password=payload.password.get_secret_value(),
        client_platform=payload.client_platform,
        device_name=payload.device_name,
    )
    return LoginResponse(
        session_id=result.session_id,
        expires_at=result.expires_at,
        account=account_response(result.account),
    )


@router.get(
    "/me",
    response_model=AccountResponse,
    responses={status.HTTP_401_UNAUTHORIZED: {"model": ErrorResponse}},
)
def get_me(account: CurrentAccount) -> AccountResponse:
    return account_response(account)


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={status.HTTP_401_UNAUTHORIZED: {"model": ErrorResponse}},
)
def logout(session_id: SessionId, service: AuthServiceDependency) -> None:
    service.logout(session_id)
