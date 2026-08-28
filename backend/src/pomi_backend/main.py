"""FastAPI application factory and ASGI entrypoint."""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from sqlalchemy import Engine
from starlette.middleware.trustedhost import TrustedHostMiddleware

from pomi_backend.api.auth import router as auth_router
from pomi_backend.api.business import BusinessError
from pomi_backend.api.cycles import cycle_error_handler
from pomi_backend.api.cycles import router as cycles_router
from pomi_backend.api.dashboard import router as dashboard_router
from pomi_backend.api.documents import router as documents_router
from pomi_backend.api.errors import (
    auth_error_handler,
    business_error_handler,
    rate_limit_error_handler,
    validation_error_handler,
)
from pomi_backend.api.health import router as health_router
from pomi_backend.api.labs import router as labs_router
from pomi_backend.api.medications import router as medications_router
from pomi_backend.api.middleware import RequestContextMiddleware, SecurityHeadersMiddleware
from pomi_backend.api.ocr import router as ocr_router, sync_router as ocr_sync_router
from pomi_backend.api.onboarding import router as onboarding_router
from pomi_backend.api.patient import router as patient_router
from pomi_backend.api.patient_notes import router as patient_notes_router
from pomi_backend.api.reconciliations import router as reconciliations_router
from pomi_backend.api.reports import router as reports_router
from pomi_backend.api.weights import router as weights_router
from pomi_backend.config import Settings
from pomi_backend.db import build_engine, build_session_factory
from pomi_backend.services.auth import AuthError
from pomi_backend.services.cycles import CycleError
from pomi_backend.services.rate_limit import RateLimitExceeded, SlidingWindowRateLimiter
from pomi_backend.services.security import PasswordManager


def create_app(*, settings: Settings | None = None, engine: Engine | None = None) -> FastAPI:
    active_settings = settings or Settings.from_env()
    docs_enabled = active_settings.environment != "production"
    app = FastAPI(
        title="Pomi API",
        debug=False,
        docs_url="/docs" if docs_enabled else None,
        redoc_url="/redoc" if docs_enabled else None,
        openapi_url="/openapi.json" if docs_enabled else None,
    )

    active_engine = engine or build_engine(active_settings.database_url)
    active_settings.storage_root.mkdir(parents=True, exist_ok=True)
    app.state.settings = active_settings
    app.state.engine = active_engine
    app.state.session_factory = build_session_factory(active_engine)
    app.state.password_manager = PasswordManager(active_settings)
    app.state.auth_rate_limiter = SlidingWindowRateLimiter(
        attempts=active_settings.auth_rate_limit_attempts,
        window_seconds=active_settings.auth_rate_limit_window_seconds,
    )
    business_timezone = ZoneInfo(active_settings.business_timezone)
    app.state.business_date_provider = lambda: datetime.now(business_timezone).date()

    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(RequestContextMiddleware)
    if active_settings.environment == "production":
        app.add_middleware(
            TrustedHostMiddleware,
            allowed_hosts=list(active_settings.allowed_hosts),
        )

    app.add_exception_handler(AuthError, auth_error_handler)
    app.add_exception_handler(CycleError, cycle_error_handler)
    app.add_exception_handler(RateLimitExceeded, rate_limit_error_handler)
    app.add_exception_handler(RequestValidationError, validation_error_handler)
    app.add_exception_handler(BusinessError, business_error_handler)
    app.include_router(auth_router)
    app.include_router(cycles_router)
    app.include_router(dashboard_router)
    app.include_router(health_router)
    app.include_router(weights_router)
    app.include_router(medications_router)
    app.include_router(patient_router)
    app.include_router(patient_notes_router)
    app.include_router(reports_router)
    app.include_router(documents_router)
    app.include_router(ocr_router)
    app.include_router(ocr_sync_router)
    app.include_router(onboarding_router)
    app.include_router(reconciliations_router)
    app.include_router(labs_router)
    return app


app = create_app()
