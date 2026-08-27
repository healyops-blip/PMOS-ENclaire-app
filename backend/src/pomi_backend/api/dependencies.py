"""FastAPI dependencies for database sessions and authentication."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from pomi_backend.db.models import UserAccount
from pomi_backend.services import (
    AuthService,
    DocumentService,
    HealthRecordService,
    ReconciliationService,
    ReportService,
)
from pomi_backend.services.auth import AuthError
from pomi_backend.services.ocr import OcrService

bearer_scheme = HTTPBearer(auto_error=False, scheme_name="SessionBearer")


def get_database_session(request: Request) -> Iterator[Session]:
    session_factory = request.app.state.session_factory
    with session_factory() as session:
        yield session


DatabaseSession = Annotated[Session, Depends(get_database_session)]


def get_auth_service(request: Request, session: DatabaseSession) -> AuthService:
    return AuthService(
        session,
        password_manager=request.app.state.password_manager,
        session_ttl_seconds=request.app.state.settings.session_ttl_seconds,
    )


AuthServiceDependency = Annotated[AuthService, Depends(get_auth_service)]


def get_session_id(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Security(bearer_scheme)],
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AuthError
    return credentials.credentials


SessionId = Annotated[str, Depends(get_session_id)]


def get_current_account(service: AuthServiceDependency, session_id: SessionId) -> UserAccount:
    return service.authenticate(session_id)


CurrentAccount = Annotated[UserAccount, Depends(get_current_account)]


def get_health_record_service(
    session: DatabaseSession, account: CurrentAccount
) -> HealthRecordService:
    return HealthRecordService(session, account)


HealthRecordServiceDependency = Annotated[HealthRecordService, Depends(get_health_record_service)]


def get_document_service(
    request: Request, session: DatabaseSession, account: CurrentAccount
) -> DocumentService:
    return DocumentService(session, account, request.app.state.settings.storage_root)


DocumentServiceDependency = Annotated[DocumentService, Depends(get_document_service)]


def get_ocr_service(
    request: Request, session: DatabaseSession, account: CurrentAccount
) -> OcrService:
    return OcrService(session, account, request.app.state.settings)


OcrServiceDependency = Annotated[OcrService, Depends(get_ocr_service)]


def get_reconciliation_service(
    session: DatabaseSession, account: CurrentAccount
) -> ReconciliationService:
    return ReconciliationService(session, account)


ReconciliationServiceDependency = Annotated[
    ReconciliationService, Depends(get_reconciliation_service)
]


def get_report_service(
    request: Request, session: DatabaseSession, account: CurrentAccount
) -> ReportService:
    return ReportService(session, account, request.app.state.settings.storage_root)


ReportServiceDependency = Annotated[ReportService, Depends(get_report_service)]
