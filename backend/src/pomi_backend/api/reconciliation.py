"""Medication reconciliation and deterministic-rule audit API."""

from typing import Annotated

from fastapi import APIRouter, Header, Request, status
from sqlalchemy import select

from pomi_backend.api.business import BusinessError, success
from pomi_backend.api.dependencies import (
    CurrentAccount,
    DatabaseSession,
    ReconciliationServiceDependency,
)
from pomi_backend.db.models import DeterministicRule, RuleExecution
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.reports import (
    DeterministicRuleUpdate,
    ReconciliationCreate,
    ReconciliationUpdate,
)
from pomi_backend.services.health_records import HealthRecordService
from pomi_backend.services.reconciliation import (
    execution_data,
    reconciliation_data,
    rule_data,
)

router = APIRouter(prefix="/api", tags=["reconciliation"])
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.post("/medication-reconciliations", status_code=status.HTTP_201_CREATED)
def create_reconciliation(
    payload: ReconciliationCreate,
    request: Request,
    service: ReconciliationServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    value, items = service.create(payload, idempotency_key)
    return success(request, reconciliation_data(value, items))


@router.get("/medication-reconciliations/{reconciliation_id}")
def get_reconciliation(
    reconciliation_id: str,
    request: Request,
    service: ReconciliationServiceDependency,
) -> dict:
    value = service.owned(reconciliation_id)
    return success(request, reconciliation_data(value, service.items(value.id)))


@router.put("/medication-reconciliations/{reconciliation_id}")
def update_reconciliation(
    reconciliation_id: str,
    payload: ReconciliationUpdate,
    request: Request,
    service: ReconciliationServiceDependency,
) -> dict:
    value, items = service.update(reconciliation_id, payload)
    return success(request, reconciliation_data(value, items))


@router.get("/deterministic-rules")
def list_rules(request: Request, session: DatabaseSession, _: CurrentAccount) -> dict:
    rules = list(
        session.scalars(
            select(DeterministicRule)
            .where(DeterministicRule.enabled.is_(True))
            .order_by(DeterministicRule.priority, DeterministicRule.rule_key)
        )
    )
    return success(request, [rule_data(rule) for rule in rules])


@router.put("/deterministic-rules/{rule_id}")
def update_rule(
    rule_id: str,
    payload: DeterministicRuleUpdate,
    request: Request,
    session: DatabaseSession,
    account: CurrentAccount,
) -> dict:
    if account.account_type != "admin":
        raise BusinessError("FORBIDDEN_RESOURCE", "Administrator access is required.", 403)
    rule = session.get(DeterministicRule, rule_id)
    if rule is None:
        raise BusinessError("RESOURCE_NOT_FOUND", "Rule was not found.", 404)
    if rule.updated_at != payload.updated_at:
        raise BusinessError("RESOURCE_VERSION_CONFLICT", "Rule has changed.", 409)
    rule.parameters = payload.parameters
    rule.priority = payload.priority
    rule.enabled = payload.enabled
    rule.updated_by_uid = account.uid
    rule.updated_at = utc_now()
    session.commit()
    session.refresh(rule)
    return success(request, rule_data(rule))


@router.get("/rule-executions/{execution_id}")
def get_rule_execution(
    execution_id: str,
    request: Request,
    session: DatabaseSession,
    account: CurrentAccount,
) -> dict:
    patient_id = HealthRecordService(session, account).profile().patient_id
    execution = session.scalar(
        select(RuleExecution).where(
            RuleExecution.id == execution_id,
            RuleExecution.patient_id == patient_id,
        )
    )
    if execution is None:
        raise BusinessError("RESOURCE_NOT_FOUND", "Rule execution was not found.", 404)
    return success(request, execution_data(execution))
