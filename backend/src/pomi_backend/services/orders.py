"""Medical-order confirmation and deterministic, atomic medication reconciliation."""

from __future__ import annotations

import re
from datetime import timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    MedicalOrder,
    Medication,
    MedicationEvent,
    MedicationReconciliation,
    MedicationReconciliationItem,
    OCRFieldResult,
    OCRResult,
    OCRTask,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import (
    MedicalOrderRepository,
    PatientRepository,
    ReconciliationRepository,
)
from pomi_backend.schemas.orders import MedicalOrderConfirmation, ReconciliationExecute
from pomi_backend.services.medications import instruction_data, medication_data
from pomi_backend.services.ocr_fallback import mark_fallback_confirmed

RECONCILIATION_RULE_VERSION = "pomi-med-reconcile-v1"

# Exact aliases only. Unknown names remain review_required; there is no fuzzy/LLM binding.
DRUG_ALIASES: dict[str, str] = {
    "二甲双胍": "rxnorm:metformin",
    "盐酸二甲双胍": "rxnorm:metformin",
    "metformin": "rxnorm:metformin",
    "优思明": "pomi:drospirenone-ethinylestradiol",
    "屈螺酮炔雌醇片": "pomi:drospirenone-ethinylestradiol",
    "维生素d3": "rxnorm:cholecalciferol",
    "胆钙化醇": "rxnorm:cholecalciferol",
    "cholecalciferol": "rxnorm:cholecalciferol",
}


def _normal(value: str) -> str:
    return re.sub(r"[\s·・,，。.]", "", value).casefold()


def standard_drug_id(name: str) -> str | None:
    normalized = _normal(name)
    return next(
        (identifier for alias, identifier in DRUG_ALIASES.items() if _normal(alias) == normalized),
        None,
    )


def _decimal(value: Decimal | None) -> float | None:
    return float(value) if value is not None else None


def medical_order_data(order: MedicalOrder) -> dict[str, Any]:
    return {
        "id": order.id,
        "medication_index": order.medication_index,
        "document_id": order.document_id,
        "document_revision_id": order.document_revision_id,
        "ocr_result_id": order.ocr_result_id,
        "ocr_task_id": order.ocr_task_id,
        "raw_order_text": order.raw_order_text,
        "drug_name": order.drug_name,
        "standard_drug_id": order.standard_drug_id,
        "specification": order.specification,
        "dosage_value": _decimal(order.dosage_value),
        "dosage_unit": order.dosage_unit,
        "frequency": order.frequency,
        "course": order.course,
        "route": order.route,
        "instructions": order.instructions,
        "order_date": order.order_date.isoformat(),
        "explicitly_stopped": order.explicitly_stopped,
        "review_required": order.review_required,
        "confirmed_by_uid": order.confirmed_by_uid,
        "confirmed_at": order.confirmed_at.isoformat(),
    }


def reconciliation_data(
    reconciliation: MedicationReconciliation,
    items: list[MedicationReconciliationItem],
    session: Session,
) -> dict[str, Any]:
    payload = []
    for item in items:
        old = session.get(Medication, item.old_medication_id) if item.old_medication_id else None
        order = (
            session.get(MedicalOrder, item.new_medical_order_id)
            if item.new_medical_order_id
            else None
        )
        payload.append(
            {
                "id": item.id,
                "position": item.position,
                "old_medication": medication_data(old) if old else None,
                "new_medical_order": medical_order_data(order) if order else None,
                "match_basis": item.match_basis,
                "suggestion": item.suggestion,
                "user_decision": item.user_decision,
                "decision_note": item.decision_note,
                "stop_date": item.stop_date.isoformat() if item.stop_date else None,
                "stop_source": item.stop_source,
                "execution_result": item.execution_result,
            }
        )
    return {
        "id": reconciliation.id,
        "ocr_task_id": reconciliation.ocr_task_id,
        "rule_version": reconciliation.rule_version,
        "status": reconciliation.status,
        "executed_at": reconciliation.executed_at.isoformat()
        if reconciliation.executed_at
        else None,
        "items": payload,
    }


class MedicalOrderService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.orders = MedicalOrderRepository(session, self.patient.patient_id)

    def confirm(
        self, task_id: str, payload: MedicalOrderConfirmation
    ) -> tuple[list[MedicalOrder], bool]:
        task = self.session.scalar(
            select(OCRTask).where(
                OCRTask.id == task_id, OCRTask.patient_id == self.patient.patient_id
            )
        )
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        if task.material_type != "medical_order":
            raise BusinessError(
                "OCR_MATERIAL_TYPE_MISMATCH",
                "Only a medical order can use this confirmation contract.",
                409,
            )
        existing = self.orders.for_task(task.id)
        if task.status == "confirmed" and existing:
            return existing, False
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_RESULT_NOT_CONFIRMABLE", "OCR result is not pending confirmation.", 409
            )
        result = self.session.scalar(select(OCRResult).where(OCRResult.task_id == task.id))
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        draft_items = result.validated_draft.get("medications")
        if not isinstance(draft_items, list) or not draft_items:
            raise BusinessError(
                "MEDICAL_ORDER_EMPTY", "No medications were extracted from the order.", 422
            )
        expected = set(range(len(draft_items)))
        actual = {item.index for item in payload.items}
        if actual != expected:
            raise BusinessError(
                "MEDICAL_ORDER_ITEMS_INCOMPLETE",
                "Every extracted medication must be confirmed separately.",
                422,
            )

        now = utc_now()
        confirmed_payload: list[dict[str, Any]] = []
        try:
            for item in sorted(payload.items, key=lambda value: value.index):
                identifier = standard_drug_id(item.drug_name.strip())
                order = MedicalOrder(
                    id=new_uuid(),
                    patient_id=self.patient.patient_id,
                    document_id=task.document_id,
                    document_revision_id=task.document_revision_id,
                    ocr_result_id=result.id,
                    ocr_task_id=task.id,
                    medication_index=item.index,
                    raw_order_text=item.raw_order_text.strip(),
                    drug_name=item.drug_name.strip(),
                    standard_drug_id=identifier,
                    specification=item.specification.strip() if item.specification else None,
                    dosage_value=item.dosage_value,
                    dosage_unit=item.dosage_unit.strip(),
                    frequency=item.frequency.strip(),
                    course=item.course.strip() if item.course else None,
                    route=item.route.strip() if item.route else None,
                    instructions=item.instructions.strip() if item.instructions else None,
                    order_date=item.order_date,
                    explicitly_stopped=item.explicitly_stopped,
                    review_required=identifier is None,
                    confirmed_by_uid=self.account.uid,
                    confirmed_at=now,
                )
                self.orders.add(order)
                confirmed_payload.append(medical_order_data(order))
            result.user_modified_data = {"medications": confirmed_payload}
            result.confirmed_data = {"medications": confirmed_payload}
            for field in self.session.scalars(
                select(OCRFieldResult).where(OCRFieldResult.result_id == result.id)
            ):
                matched = re.search(r"medications(?:\[|\.)(\d+)\]?\.(\w+)$", field.field_path)
                if matched is None:
                    continue
                index, name = int(matched.group(1)), matched.group(2)
                if index >= len(confirmed_payload) or name not in confirmed_payload[index]:
                    continue
                field.user_value = confirmed_payload[index][name]
                field.confirmation_status = (
                    "accepted" if field.parsed_value == field.user_value else "corrected"
                )
                field.updated_at = now
            task.status = "confirmed"
            task.updated_at = now
            mark_fallback_confirmed(self.session, task, uid=self.account.uid, confirmed_at=now)
            self.session.commit()
        except Exception:
            self.session.rollback()
            raise
        return self.orders.for_task(task.id), True


class ReconciliationService:
    def __init__(self, session: Session, account: UserAccount) -> None:
        self.session = session
        self.account = account
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.orders = MedicalOrderRepository(session, self.patient.patient_id)
        self.repository = ReconciliationRepository(session, self.patient.patient_id)

    def owned(self, reconciliation_id: str) -> MedicationReconciliation:
        reconciliation = self.repository.get(reconciliation_id)
        if reconciliation is None:
            raise BusinessError(
                "RESOURCE_NOT_FOUND", "Medication reconciliation was not found.", 404
            )
        return reconciliation

    def create(self, task_id: str) -> tuple[MedicationReconciliation, bool]:
        existing = self.repository.for_task(task_id)
        if existing is not None:
            return existing, False
        task = self.session.scalar(
            select(OCRTask).where(
                OCRTask.id == task_id, OCRTask.patient_id == self.patient.patient_id
            )
        )
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        if task.status != "confirmed" or task.material_type != "medical_order":
            raise BusinessError(
                "MEDICAL_ORDER_NOT_CONFIRMED", "All order medications must be confirmed first.", 409
            )
        orders = self.orders.for_task(task.id)
        result = self.session.scalar(select(OCRResult).where(OCRResult.task_id == task.id))
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        draft_count = len(result.validated_draft.get("medications") or [])
        if not orders or len(orders) != draft_count:
            raise BusinessError(
                "MEDICAL_ORDER_ITEMS_INCOMPLETE",
                "All order medications must be confirmed first.",
                409,
            )

        active = list(
            self.session.scalars(
                select(Medication).where(
                    Medication.patient_id == self.patient.patient_id,
                    Medication.status.in_(("active", "paused")),
                )
            )
        )
        matched: set[str] = set()
        suggestions: list[tuple[Medication | None, MedicalOrder | None, str, dict[str, Any]]] = []
        for order in orders:
            match = next(
                (
                    med
                    for med in active
                    if med.id not in matched
                    and self._identifier(med) == order.standard_drug_id
                    and order.standard_drug_id is not None
                ),
                None,
            )
            if order.standard_drug_id is None:
                suggestion, basis = "manual_review", {"reason": "unmapped_new_drug_name"}
            elif order.explicitly_stopped:
                suggestion, basis = (
                    ("stopped", {"standard_drug_id": order.standard_drug_id, "explicit_stop": True})
                    if match
                    else ("manual_review", {"reason": "stop_target_not_found"})
                )
            elif match is None:
                suggestion, basis = "added", {"standard_drug_id": order.standard_drug_id}
            elif self._same_instruction(match, order):
                suggestion, basis = (
                    "unchanged",
                    {"standard_drug_id": order.standard_drug_id, "dose_and_frequency_equal": True},
                )
            else:
                suggestion, basis = (
                    "adjusted",
                    {"standard_drug_id": order.standard_drug_id, "dose_and_frequency_equal": False},
                )
            if match:
                matched.add(match.id)
            suggestions.append((match, order, suggestion, basis))
        for medication in active:
            if medication.id not in matched:
                suggestions.append(
                    (
                        medication,
                        None,
                        "uncertain",
                        {"reason": "not_present_in_new_order", "automatic_stop": False},
                    )
                )

        reconciliation = MedicationReconciliation(
            id=new_uuid(),
            patient_id=self.patient.patient_id,
            ocr_task_id=task.id,
            rule_version=RECONCILIATION_RULE_VERSION,
            created_by_uid=self.account.uid,
        )
        items = [
            MedicationReconciliationItem(
                id=new_uuid(),
                patient_id=self.patient.patient_id,
                reconciliation_id=reconciliation.id,
                position=index,
                old_medication_id=old.id if old else None,
                new_medical_order_id=order.id if order else None,
                suggestion=suggestion,
                match_basis=basis,
            )
            for index, (old, order, suggestion, basis) in enumerate(suggestions)
        ]
        try:
            self.repository.add(reconciliation, items)
            self.session.commit()
        except Exception:
            self.session.rollback()
            raise
        return reconciliation, True

    def data(self, reconciliation: MedicationReconciliation) -> dict[str, Any]:
        return reconciliation_data(
            reconciliation, self.repository.items(reconciliation.id), self.session
        )

    def execute(
        self, reconciliation_id: str, payload: ReconciliationExecute
    ) -> MedicationReconciliation:
        reconciliation = self.owned(reconciliation_id)
        if reconciliation.status == "executed":
            return reconciliation
        items = self.repository.items(reconciliation.id)
        decisions = {decision.item_id: decision for decision in payload.decisions}
        if set(decisions) != {item.id for item in items}:
            raise BusinessError(
                "RECONCILIATION_DECISIONS_INCOMPLETE",
                "Every reconciliation item needs one decision.",
                422,
            )
        for item in items:
            decision = decisions[item.id]
            if item.suggestion == "manual_review" and decision.decision == "accept":
                raise BusinessError(
                    "MANUAL_REVIEW_REQUIRED",
                    "Unmapped medications cannot be executed automatically.",
                    422,
                )
            old = (
                self.session.get(Medication, item.old_medication_id)
                if item.old_medication_id
                else None
            )
            order = (
                self.session.get(MedicalOrder, item.new_medical_order_id)
                if item.new_medical_order_id
                else None
            )
            if item.old_medication_id and (
                old is None or old.patient_id != self.patient.patient_id
            ):
                raise BusinessError(
                    "RECONCILIATION_STATE_INVALID",
                    "The old medication is no longer available.",
                    409,
                )
            if item.new_medical_order_id and (
                order is None or order.patient_id != self.patient.patient_id
            ):
                raise BusinessError(
                    "RECONCILIATION_STATE_INVALID",
                    "The confirmed order is no longer available.",
                    409,
                )
            if (
                decision.decision == "accept"
                and old is not None
                and order is not None
                and old.start_date is not None
                and order.order_date < old.start_date
            ):
                raise BusinessError(
                    "INVALID_EVENT_DATE",
                    "The order date cannot precede the medication version.",
                    422,
                )
            if (
                item.suggestion == "stopped"
                and decision.decision == "accept"
                and (decision.stop_date is None or not decision.stop_source)
            ):
                raise BusinessError(
                    "STOP_EVIDENCE_REQUIRED",
                    "Stopping requires a date and information source.",
                    422,
                )

        try:
            for item in items:
                decision = decisions[item.id]
                item.user_decision = decision.decision
                item.decision_note = decision.note
                item.stop_date = decision.stop_date
                item.stop_source = decision.stop_source
                if decision.decision != "accept" or item.suggestion in {"unchanged", "uncertain"}:
                    item.execution_result = {
                        "action": "none",
                        "safety": "current_medication_unchanged",
                    }
                    continue
                old = (
                    self.session.get(Medication, item.old_medication_id)
                    if item.old_medication_id
                    else None
                )
                order = (
                    self.session.get(MedicalOrder, item.new_medical_order_id)
                    if item.new_medical_order_id
                    else None
                )
                if item.suggestion == "added" and order:
                    created = self._create_medication(order, None)
                    item.execution_result = {"action": "created", "medication_id": created.id}
                elif item.suggestion == "adjusted" and old and order:
                    created = self._create_medication(order, old)
                    item.execution_result = {
                        "action": "version_created",
                        "medication_id": created.id,
                        "replaces_medication_id": old.id,
                    }
                elif item.suggestion == "stopped" and old and order:
                    self._stop_medication(old, order, decision.stop_date, decision.stop_source)  # type: ignore[arg-type]
                    item.execution_result = {"action": "stopped", "medication_id": old.id}
                else:
                    raise BusinessError(
                        "RECONCILIATION_STATE_INVALID",
                        "The reconciliation item is no longer executable.",
                        409,
                    )
            now = utc_now()
            reconciliation.status = "executed"
            reconciliation.executed_by_uid = self.account.uid
            reconciliation.executed_at = now
            reconciliation.updated_at = now
            self.session.commit()
        except Exception:
            self.session.rollback()
            raise
        return reconciliation

    @staticmethod
    def _identifier(medication: Medication) -> str | None:
        return medication.standard_drug_id or standard_drug_id(medication.drug_name)

    @staticmethod
    def _same_instruction(medication: Medication, order: MedicalOrder) -> bool:
        return (
            medication.dosage_value == order.dosage_value
            and _normal(medication.dosage_unit or "") == _normal(order.dosage_unit)
            and _normal(medication.frequency or "") == _normal(order.frequency)
        )

    def _create_medication(self, order: MedicalOrder, old: Medication | None) -> Medication:
        previous = instruction_data(old) if old else None
        replacement_status = old.status if old else "active"
        if old is not None:
            old.status = "stopped"
            old.end_date = max(
                old.start_date or order.order_date, order.order_date - timedelta(days=1)
            )
            old.updated_at = utc_now()
        medication = Medication(
            id=new_uuid(),
            patient_id=self.patient.patient_id,
            drug_name=order.drug_name,
            standard_drug_id=order.standard_drug_id,
            source_category="prescribed",
            specification=order.specification,
            dosage_value=order.dosage_value,
            dosage_unit=order.dosage_unit,
            frequency=order.frequency,
            route=order.route,
            status=replacement_status,
            start_date=order.order_date,
            replaces_medication_id=old.id if old else None,
        )
        self.session.add(medication)
        self.session.flush()
        self.session.add(
            MedicationEvent(
                id=new_uuid(),
                patient_id=self.patient.patient_id,
                medication_id=medication.id,
                event_type="adjusted" if old else "created",
                event_date=order.order_date,
                old_instruction=previous,
                new_instruction=instruction_data(medication),
                source_type="medical_order",
                source_document_id=order.document_id,
                acted_by_uid=self.account.uid,
                note=f"Confirmed medical order {order.id}",
            )
        )
        return medication

    def _stop_medication(
        self, old: Medication, order: MedicalOrder, stop_date: Any, stop_source: str
    ) -> None:
        previous = instruction_data(old)
        old.status = "stopped"
        old.end_date = stop_date
        old.updated_at = utc_now()
        self.session.add(
            MedicationEvent(
                id=new_uuid(),
                patient_id=self.patient.patient_id,
                medication_id=old.id,
                event_type="stopped",
                event_date=stop_date,
                old_instruction=previous,
                new_instruction=instruction_data(old),
                source_type="medical_order",
                source_document_id=order.document_id,
                acted_by_uid=self.account.uid,
                stop_source=stop_source,
                note=f"Explicit stop in confirmed medical order {order.id}",
            )
        )
