"""Deterministic medication reconciliation and rule-audit operations."""

from __future__ import annotations

import json
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    DeterministicRule,
    Document,
    MedicalOrder,
    Medication,
    MedicationEvent,
    MedicationReconciliation,
    MedicationReconciliationItem,
    RuleExecution,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.schemas.reports import ReconciliationCreate, ReconciliationUpdate
from pomi_backend.services.health_records import HealthRecordService


def _medication_instruction(medication: Medication) -> dict[str, Any]:
    return {
        "drug_name": medication.drug_name,
        "specification": medication.specification,
        "dosage_text": medication.dosage_text,
        "dosage_value": medication.dosage_value,
        "dosage_unit": medication.dosage_unit,
        "frequency": medication.frequency,
        "route": medication.route,
    }


def _order_instruction(order: MedicalOrder) -> dict[str, Any]:
    return {
        "source_text": order.source_text,
        "drug_name": order.drug_name,
        "specification": order.specification,
        "dosage_text": order.dosage_text,
        "dosage_value": order.dosage_value,
        "dosage_unit": order.dosage_unit,
        "frequency": order.frequency,
        "duration": order.duration,
        "route": order.route,
        "instruction": order.instruction,
        "prescribed_at": order.prescribed_at.isoformat() if order.prescribed_at else None,
    }


def item_data(item: MedicationReconciliationItem) -> dict[str, Any]:
    return {
        "id": item.id,
        "existing_medication_id": item.existing_medication_id,
        "new_medical_order_id": item.new_medical_order_id,
        "medication_concept_id": item.medication_concept_id,
        "drug_name": item.drug_name,
        "comparison_type": item.comparison_type,
        "rule_id": item.rule_id,
        "old_instruction": item.old_instruction,
        "new_instruction": item.new_instruction,
        "differences": item.differences,
        "user_decision": item.user_decision,
        "decision_note": item.decision_note,
    }


def reconciliation_data(
    reconciliation: MedicationReconciliation,
    items: list[MedicationReconciliationItem],
) -> dict[str, Any]:
    return {
        "id": reconciliation.id,
        "source_document_id": reconciliation.source_document_id,
        "status": reconciliation.status,
        "summary": reconciliation.summary,
        "items": [item_data(item) for item in items],
        "created_at": reconciliation.created_at.isoformat(),
        "confirmed_at": reconciliation.confirmed_at.isoformat()
        if reconciliation.confirmed_at
        else None,
    }


class ReconciliationService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account
        self.health = HealthRecordService(session, account)

    def create(
        self, payload: ReconciliationCreate, idempotency_key: str
    ) -> tuple[MedicationReconciliation, list[MedicationReconciliationItem]]:
        existing = self.session.scalar(
            select(MedicationReconciliation).where(
                MedicationReconciliation.created_by_uid == self.account.uid,
                MedicationReconciliation.idempotency_key == idempotency_key,
            )
        )
        if existing is not None:
            return existing, self.items(existing.id)
        profile = self.health.profile()
        document = self.session.scalar(
            select(Document).where(
                Document.id == payload.source_document_id,
                Document.patient_id == profile.patient_id,
                Document.document_type == "medical_order",
                Document.deleted_at.is_(None),
            )
        )
        if document is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Medical order was not found.", 404)
        statement = select(MedicalOrder).where(
            MedicalOrder.document_id == document.id,
            MedicalOrder.patient_id == profile.patient_id,
        )
        if payload.medical_order_ids:
            statement = statement.where(MedicalOrder.id.in_(payload.medical_order_ids))
        orders = list(self.session.scalars(statement))
        if not orders:
            raise BusinessError(
                "RECONCILIATION_REQUIRED", "No confirmed medical orders were found.", 409
            )
        reconciliation = MedicationReconciliation(
            patient_id=profile.patient_id,
            source_document_id=document.id,
            summary={"order_count": len(orders)},
            idempotency_key=idempotency_key,
            created_by_uid=self.account.uid,
        )
        self.session.add(reconciliation)
        self.session.flush()
        records: list[MedicationReconciliationItem] = []
        for order in orders:
            medication = self.session.scalar(
                select(Medication)
                .where(
                    Medication.patient_id == profile.patient_id,
                    Medication.normalized_drug_name == order.normalized_drug_name,
                    Medication.current_status == "active",
                )
                .order_by(Medication.created_at.desc())
                .limit(1)
            )
            old = _medication_instruction(medication) if medication else None
            new = _order_instruction(order)
            differences = {
                key: {"old": old.get(key) if old else None, "new": new.get(key)}
                for key in ("specification", "dosage_text", "frequency", "route")
                if old is None or old.get(key) != new.get(key)
            }
            if medication is None:
                comparison_type = "added"
            elif not differences:
                comparison_type = "unchanged"
            else:
                comparison_type = "adjusted"
            item = MedicationReconciliationItem(
                reconciliation_id=reconciliation.id,
                existing_medication_id=medication.id if medication else None,
                new_medical_order_id=order.id,
                drug_name=order.drug_name,
                comparison_type=comparison_type,
                old_instruction=old,
                new_instruction=new,
                differences=differences,
            )
            self.session.add(item)
            records.append(item)
        self.session.commit()
        self.session.refresh(reconciliation)
        for item in records:
            self.session.refresh(item)
        return reconciliation, records

    def owned(self, reconciliation_id: str) -> MedicationReconciliation:
        value = self.session.scalar(
            select(MedicationReconciliation).where(
                MedicationReconciliation.id == reconciliation_id,
                MedicationReconciliation.patient_id == self.health.profile().patient_id,
            )
        )
        if value is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Reconciliation was not found.", 404)
        return value

    def items(self, reconciliation_id: str) -> list[MedicationReconciliationItem]:
        return list(
            self.session.scalars(
                select(MedicationReconciliationItem)
                .where(MedicationReconciliationItem.reconciliation_id == reconciliation_id)
                .order_by(MedicationReconciliationItem.id)
            )
        )

    def update(
        self, reconciliation_id: str, payload: ReconciliationUpdate
    ) -> tuple[MedicationReconciliation, list[MedicationReconciliationItem]]:
        reconciliation = self.owned(reconciliation_id)
        if reconciliation.status != "pending":
            raise BusinessError(
                "RESOURCE_VERSION_CONFLICT", "Reconciliation is already closed.", 409
            )
        items = self.items(reconciliation.id)
        decisions = {decision.item_id: decision for decision in payload.items}
        if set(decisions) != {item.id for item in items}:
            raise BusinessError(
                "VALIDATION_ERROR", "Every reconciliation item requires one decision.", 422
            )
        if payload.status == "confirmed" and any(
            decision.user_decision == "needs_review" for decision in decisions.values()
        ):
            raise BusinessError(
                "RECONCILIATION_REQUIRED", "Items requiring review cannot be confirmed.", 409
            )
        for item in items:
            decision = decisions[item.id]
            item.user_decision = decision.user_decision
            item.decision_note = decision.decision_note
            item.stop_date = decision.stop_date
            item.stop_source = decision.stop_source
            if payload.status == "confirmed":
                self._apply_decision(item)
        reconciliation.status = payload.status
        if payload.status == "confirmed":
            reconciliation.confirmed_by_uid = self.account.uid
            reconciliation.confirmed_at = utc_now()
        self.session.commit()
        self.session.refresh(reconciliation)
        return reconciliation, items

    def _apply_decision(self, item: MedicationReconciliationItem) -> None:
        if item.user_decision in {"keep_existing", "needs_review"}:
            return
        medication = (
            self.session.get(Medication, item.existing_medication_id)
            if item.existing_medication_id
            else None
        )
        order = (
            self.session.get(MedicalOrder, item.new_medical_order_id)
            if item.new_medical_order_id
            else None
        )
        if item.user_decision == "confirm_stopped":
            if medication is None or item.stop_date is None or item.stop_source is None:
                raise BusinessError("VALIDATION_ERROR", "Stop decision is incomplete.", 422)
            old = _medication_instruction(medication)
            medication.current_status = "stopped"
            medication.end_date = item.stop_date
            medication.updated_at = utc_now()
            self.session.add(
                MedicationEvent(
                    patient_id=medication.patient_id,
                    medication_id=medication.id,
                    event_type="stopped",
                    event_date=item.stop_date,
                    old_instruction_json=json.dumps(old, ensure_ascii=False),
                    new_instruction_json=json.dumps(
                        _medication_instruction(medication), ensure_ascii=False
                    ),
                    confirmed_by_uid=self.account.uid,
                    confirmed_at=utc_now(),
                    stop_source=item.stop_source,
                    note=item.decision_note,
                )
            )
            return
        if order is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "Medical order is missing.", 404)
        if medication is None:
            medication = Medication(
                patient_id=order.patient_id,
                drug_name=order.drug_name,
                normalized_drug_name=order.normalized_drug_name,
                specification=order.specification,
                dosage_text=order.dosage_text,
                dosage_value=order.dosage_value,
                dosage_unit=order.dosage_unit,
                frequency=order.frequency,
                route=order.route,
                start_date=order.prescribed_at,
                source_type="medical_order",
                source_document_id=order.document_id,
            )
            self.session.add(medication)
            self.session.flush()
            event_type = "started"
            old = None
        else:
            old = _medication_instruction(medication)
            medication.specification = order.specification
            medication.dosage_text = order.dosage_text
            medication.dosage_value = order.dosage_value
            medication.dosage_unit = order.dosage_unit
            medication.frequency = order.frequency
            medication.route = order.route
            medication.current_status = "active"
            medication.updated_at = utc_now()
            event_type = "continued" if item.comparison_type == "unchanged" else "adjusted"
        self.session.add(
            MedicationEvent(
                patient_id=medication.patient_id,
                medication_id=medication.id,
                event_type=event_type,
                event_date=order.prescribed_at or utc_now().date(),
                old_instruction_json=json.dumps(old, ensure_ascii=False) if old else None,
                new_instruction_json=json.dumps(
                    _medication_instruction(medication), ensure_ascii=False
                ),
                source_document_id=order.document_id,
                confirmed_by_uid=self.account.uid,
                confirmed_at=utc_now(),
                note=item.decision_note,
            )
        )


def rule_data(rule: DeterministicRule) -> dict[str, Any]:
    return {
        "id": rule.id,
        "rule_key": rule.rule_key,
        "rule_type": rule.rule_type,
        "rule_name": rule.rule_name,
        "parameters": rule.parameters,
        "priority": rule.priority,
        "enabled": rule.enabled,
        "updated_at": rule.updated_at.isoformat(),
    }


def execution_data(execution: RuleExecution) -> dict[str, Any]:
    return {
        "id": execution.id,
        "rule_id": execution.rule_id,
        "source_type": execution.source_type,
        "source_id": execution.source_id,
        "input_digest": execution.input_digest,
        "input": execution.input,
        "output": execution.output,
        "explanation": execution.explanation,
        "executed_at": execution.executed_at.isoformat(),
    }
