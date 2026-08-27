"""FastAPI dependencies for database sessions and authentication."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from pomi_backend.db.models import UserAccount
from pomi_backend.services import AuthService
from pomi_backend.services.auth import AuthError
from pomi_backend.services.medications import MedicationService
from pomi_backend.services.patient import PatientProfileService
from pomi_backend.services.patient_notes import PatientNoteService

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


def get_patient_profile_service(
    session: DatabaseSession, account: CurrentAccount
) -> PatientProfileService:
    return PatientProfileService(session, account)


PatientProfileServiceDependency = Annotated[
    PatientProfileService, Depends(get_patient_profile_service)
]


def get_patient_note_service(
    session: DatabaseSession, account: CurrentAccount
) -> PatientNoteService:
    return PatientNoteService(session, account)


PatientNoteServiceDependency = Annotated[PatientNoteService, Depends(get_patient_note_service)]


def get_medication_service(
    request: Request,
    session: DatabaseSession,
    account: CurrentAccount,
) -> MedicationService:
    return MedicationService(
        session,
        account,
        request.app.state.business_date_provider(),
    )


MedicationServiceDependency = Annotated[MedicationService, Depends(get_medication_service)]
