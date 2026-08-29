"""Medical-order confirmation and deterministic, atomic medication reconciliation."""

from __future__ import annotations

import json
import re
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import (
    MedicalOrder,
    Medication,
    MedicationEvent,
    MedicationReconciliation,
    MedicationReconciliationItem,
    OCRResult,
    OCRTask,
    UserAccount,
)
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import (
    DocumentRepository,
    MedicalOrderRepository,
    OCRRepository,
    PatientRepository,
    ReconciliationRepository,
)
from pomi_backend.schemas.orders import MedicalOrderConfirmation, ReconciliationExecute
from pomi_backend.services.medications import instruction_data, medication_data

RECONCILIATION_RULE_VERSION = "pomi-med-reconcile-v1"

# Exact aliases only. Unknown names remain review_required; there is no fuzzy/LLM binding.
DRUG_ALIASES: dict[str, str] = {
    "二甲双胍": "rxnorm:metformin",
    "盐酸二甲双胍": "rxnorm:metformin",
    "metformin": "rxnorm:metformin",
    "叶酸": "pomi:folic-acid",
    "folicacid": "pomi:folic-acid",
    "炔雌醇环丙孕酮": "pomi:cyproterone-ethinylestradiol",
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
        "source_text": order.raw_order_text,
        "drug_name": order.drug_name,
        "standard_drug_id": order.standard_drug_id,
        "specification": order.specification,
        "dosage_value": _decimal(order.dosage_value),
        "dosage_unit": order.dosage_unit,
        "frequency": order.frequency,
        "duration": order.course,
        "route": order.route,
        "instruction": order.instructions,
        "prescribed_at": order.order_date.isoformat(),
        "explicitly_stopped": order.explicitly_stopped,
        "review_required": order.review_required,
        "original_item_data": order.original_item_data,
        "confirmed_item_data": order.confirmed_item_data,
        "confirmed_by_uid": order.confirmed_by_uid,
        "confirmed_at": order.confirmed_at.isoformat(),
    }


def medical_order_p0(orders: list[MedicalOrder]) -> dict[str, int | float]:
    """Measure the three safety-critical fields against the OCR draft."""
    total = len(orders) * 3
    valid = 0
    exact = 0
    for order in orders:
        original = order.original_item_data or {}
        confirmed = order.confirmed_item_data or {}
        valid += int(bool(order.drug_name.strip()))
        valid += int(order.dosage_value > 0)
        valid += int(bool(order.frequency.strip()))
        for field in ("drug_name", "dosage_value", "frequency"):
            exact += int(
                str(confirmed.get(field) or "").strip() == str(original.get(field) or "").strip()
            )
    return {
        "total_fields": total,
        "valid_fields": valid,
        "invalid_fields": total - valid,
        "valid_rate": 1.0 if total == 0 else round(valid / total, 4),
        "ocr_exact_match_fields": exact,
        "user_corrected_fields": total - exact,
        "ocr_exact_match_rate": 1.0 if total == 0 else round(exact / total, 4),
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
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        *,
        business_date: date,
    ) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date
        self.patient = PatientRepository(session).get_or_create(account.uid)
        self.orders = MedicalOrderRepository(session, self.patient.patient_id)
        self.ocr = OCRRepository(session, self.patient.patient_id)
        self.documents = DocumentRepository(session, self.patient.patient_id)

    def confirm(
        self, task_id: str, payload: MedicalOrderConfirmation
    ) -> tuple[list[MedicalOrder], bool]:
        task = self.ocr.get(task_id)
        if task is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR task was not found.", 404)
        if task.material_type != "medical_order":
            raise BusinessError(
                "OCR_MATERIAL_TYPE_MISMATCH",
                "Only a medical order can use this confirmation contract.",
                409,
            )
        result = self.ocr.result(task.id)
        if result is None:
            raise BusinessError("OCR_RESULT_NOT_READY", "OCR result is not ready.", 409)
        if (
            payload.result_id != result.id
            or payload.expected_revision_id != task.document_revision_id
        ):
            raise BusinessError(
                "OCR_CONFIRMATION_VERSION_CONFLICT",
                "The OCR result or document revision has changed.",
                409,
            )
        canonical_payload = json.loads(
            json.dumps(payload.model_dump(mode="json"), ensure_ascii=False, sort_keys=True)
        )
        existing = self.orders.for_task(task.id)
        if task.status == "confirmed":
            if result.confirmed_data != canonical_payload:
                raise BusinessError(
                    "OCR_ALREADY_CONFIRMED",
                    "The task was already confirmed with different data.",
                    409,
                )
            if not existing:
                raise BusinessError(
                    "OCR_CONFIRMATION_INCOMPLETE",
                    "The confirmed task has no matching formal orders.",
                    409,
                )
            return existing, False
        if task.status != "pending_confirmation":
            raise BusinessError(
                "OCR_RESULT_NOT_CONFIRMABLE", "OCR result is not pending confirmation.", 409
            )
        if (
            self.documents.get(task.document_id) is None
            or self.documents.revision(task.document_id, task.document_revision_id) is None
        ):
            raise BusinessError("RESOURCE_NOT_FOUND", "OCR source revision was not found.", 404)
        draft_items = result.validated_draft.get("orders")
        if not isinstance(draft_items, list) or not draft_items:
            raise BusinessError(
                "MEDICAL_ORDER_EMPTY", "No medications were extracted from the order.", 422
            )
        expected = set(range(len(draft_items)))
        actual = {item.source_index for item in payload.items}
        if actual != expected:
            raise BusinessError(
                "MEDICAL_ORDER_ITEMS_INCOMPLETE",
                "Every extracted medication must be confirmed separately.",
                422,
            )

        invalid_dates = [
            item.source_index
            for item in payload.items
            if item.prescribed_at.year < 1900 or item.prescribed_at > self.business_date
        ]
        if invalid_dates:
            raise BusinessError(
                "MEDICAL_ORDER_INVALID_DATE",
                "An order date is outside the supported range.",
                422,
                details={
                    "business_date": self.business_date.isoformat(),
                    "fields": [
                        {
                            "path": f"items.{index}.prescribed_at",
                            "code": "MEDICAL_ORDER_DATE_OUT_OF_RANGE",
                            "message": "开具日期必须在 1900-01-01 与服务器业务日期之间。",
                        }
                        for index in invalid_dates
                    ],
                },
            )
        if not self.ocr.claim_confirmation(task.id, now=utc_now()):
            self.session.rollback()
            current_task = self.ocr.get(task_id)
            current_result = self.ocr.result(task_id)
            if current_task is not None and current_result is not None:
                if current_task.status == "confirmed":
                    if current_result.confirmed_data != canonical_payload:
                        raise BusinessError(
                            "OCR_ALREADY_CONFIRMED",
                            "The task was already confirmed with different data.",
                            409,
                        )
                    return self.orders.for_task(task_id), False
            raise BusinessError(
                "OCR_CONFIRMATION_IN_PROGRESS",
                "Another confirmation request is currently being processed.",
                409,
            )

        now = utc_now()
        try:
            for item in sorted(payload.items, key=lambda value: value.source_index):
                identifier = standard_drug_id(item.drug_name.strip())
                confirmed_item = item.model_dump(mode="json")
                original_item = draft_items[item.source_index]
                order = MedicalOrder(
                    id=new_uuid(),
                    patient_id=self.patient.patient_id,
                    document_id=task.document_id,
                    document_revision_id=task.document_revision_id,
                    ocr_result_id=result.id,
                    ocr_task_id=task.id,
                    medication_index=item.source_index,
                    raw_order_text=item.source_text,
                    drug_name=item.drug_name.strip(),
                    standard_drug_id=identifier,
                    specification=item.specification.strip() if item.specification else None,
                    dosage_value=item.dosage_value,
                    dosage_unit=item.dosage_unit.strip(),
                    frequency=item.frequency.strip(),
                    course=item.duration.strip() if item.duration else None,
                    route=item.route.strip() if item.route else None,
                    instructions=item.instruction.strip() if item.instruction else None,
                    order_date=item.prescribed_at,
                    explicitly_stopped=item.explicitly_stopped,
                    review_required=(
                        identifier is None or not item.specification or not item.duration
                    ),
                    original_item_data=original_item,
                    confirmed_item_data=confirmed_item,
                    confirmed_by_uid=self.account.uid,
                    confirmed_at=now,
                )
                self.orders.add(order)
            result.user_modified_data = canonical_payload
            result.confirmed_data = canonical_payload
            confirmed_by_index = {
                item.source_index: item.model_dump(mode="json") for item in payload.items
            }
            for field in self.ocr.fields(result.id):
                matched = re.fullmatch(r"orders\.(\d+)\.(\w+)", field.field_path)
                if matched is None:
                    if field.field_path == "prescribed_at":
                        field.user_value = payload.items[0].prescribed_at.isoformat()
                    else:
                        field.user_value = field.parsed_value
                else:
                    index, name = int(matched.group(1)), matched.group(2)
                    field.user_value = confirmed_by_index.get(index, {}).get(
                        name, draft_items[index].get(name)
                    )
                field.confirmation_status = (
                    "confirmed" if field.parsed_value == field.user_value else "edited"
                )
                field.updated_at = now
            task.status = "confirmed"
            task.finished_at = task.finished_at or now
            task.updated_at = now
            self.session.commit()
        except IntegrityError:
            self.session.rollback()
            current_result = self.ocr.result(task_id)
            if current_result is not None and current_result.confirmed_data == canonical_payload:
                return self.orders.for_task(task_id), False
            raise
        except Exception:
            self.session.rollback()
            raise
        return self.orders.for_task(task.id), True


class ReconciliationService:
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        *,
        business_date: date,
    ) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date
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
        draft_count = len(result.validated_draft.get("orders") or [])
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
        except IntegrityError:
            self.session.rollback()
            existing = self.repository.for_task(task_id)
            if existing is not None:
                return existing, False
            raise
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
        canonical_payload = json.loads(
            json.dumps(payload.model_dump(mode="json"), ensure_ascii=False, sort_keys=True)
        )
        if reconciliation.status == "executed":
            if reconciliation.execution_payload != canonical_payload:
                raise BusinessError(
                    "RECONCILIATION_ALREADY_EXECUTED",
                    "The reconciliation was already executed with different decisions.",
                    409,
                )
            return reconciliation
        if reconciliation.status != "draft":
            raise BusinessError(
                "RECONCILIATION_IN_PROGRESS",
                "Another execution request is currently being processed.",
                409,
            )
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
            if decision.decision == "accept" and old is not None:
                event_date = (
                    (decision.stop_date if item.suggestion == "stopped" else order.order_date)
                    if order is not None
                    else decision.stop_date
                )
                latest_event_date = self.session.scalar(
                    select(func.max(MedicationEvent.event_date)).where(
                        MedicationEvent.patient_id == self.patient.patient_id,
                        MedicationEvent.medication_id == old.id,
                    )
                )
                if event_date is not None and (
                    (old.start_date is not None and event_date < old.start_date)
                    or (latest_event_date is not None and event_date < latest_event_date)
                ):
                    raise BusinessError(
                        "INVALID_EVENT_DATE",
                        "The medication change cannot precede its current event history.",
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
            if decision.stop_date is not None and (
                decision.stop_date.year < 1900 or decision.stop_date > self.business_date
            ):
                raise BusinessError(
                    "INVALID_EVENT_DATE",
                    "The stop date is outside the supported range.",
                    422,
                    details={"business_date": self.business_date.isoformat()},
                )

        claimed = self.session.execute(
            update(MedicationReconciliation)
            .where(
                MedicationReconciliation.id == reconciliation.id,
                MedicationReconciliation.patient_id == self.patient.patient_id,
                MedicationReconciliation.status == "draft",
            )
            .values(status="executing", updated_at=utc_now())
        )
        if claimed.rowcount != 1:
            self.session.rollback()
            current = self.owned(reconciliation_id)
            if current.status == "executed" and current.execution_payload == canonical_payload:
                return current
            if current.status == "executed":
                raise BusinessError(
                    "RECONCILIATION_ALREADY_EXECUTED",
                    "The reconciliation was already executed with different decisions.",
                    409,
                )
            raise BusinessError(
                "RECONCILIATION_IN_PROGRESS",
                "Another execution request is currently being processed.",
                409,
            )
        reconciliation.status = "executing"

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
            reconciliation.execution_payload = canonical_payload
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
