from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPOSITORY_ROOT / "contracts/openapi/pomi-api-v1.yaml"


class _UniqueKeyLoader(yaml.SafeLoader):
    pass


def _construct_unique_mapping(
    loader: _UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise AssertionError(
                f"duplicate YAML key {key!r} at line {key_node.start_mark.line + 1}"
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


_UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)


def load_contract() -> dict[str, Any]:
    contract = yaml.load(
        OPENAPI_PATH.read_text(encoding="utf-8"),
        Loader=_UniqueKeyLoader,
    )
    assert isinstance(contract, dict)
    return contract


def test_all_local_schema_references_resolve() -> None:
    contract = load_contract()
    schemas = contract["components"]["schemas"]

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            reference = value.get("$ref")
            if isinstance(reference, str) and reference.startswith("#/components/schemas/"):
                assert reference.removeprefix("#/components/schemas/") in schemas
            for nested in value.values():
                visit(nested)
        elif isinstance(value, list):
            for nested in value:
                visit(nested)

    visit(contract)


def test_medication_contract_preserves_versions_and_pause_resume_events() -> None:
    schemas = load_contract()["components"]["schemas"]

    assert schemas["MedicationStatus"]["enum"] == ["active", "paused", "stopped"]
    assert schemas["MedicationEventType"]["enum"] == [
        "created",
        "adjusted",
        "paused",
        "resumed",
        "stopped",
    ]
    assert schemas["MedicationUpdateEventType"]["enum"] == [
        "adjusted",
        "paused",
        "resumed",
        "stopped",
    ]
    assert schemas["MedicationPage"]["allOf"][1]["properties"]["server_date"]["format"] == ("date")
    medication_properties = schemas["Medication"]["allOf"][1]["properties"]
    assert medication_properties["replaces_medication_id"]["format"] == "uuid"


def test_medication_adherence_contract_exposes_edit_window_and_audit_fields() -> None:
    contract = load_contract()
    schemas = contract["components"]["schemas"]
    paths = contract["paths"]

    daily = schemas["MedicationDaily"]
    assert {"recorded_by_uid", "editable"} <= set(daily["required"])
    assert daily["properties"]["editable"]["type"] == "boolean"

    history = schemas["MedicationDailyRange"]["allOf"][1]
    assert {"business_date", "editable_from"} <= set(history["required"])
    assert history["properties"]["business_date"]["format"] == "date"

    mutation = schemas["MedicationDailyMutation"]["allOf"][1]
    assert {"business_date", "editable_from", "month_summary"} == set(mutation["required"])
    response = paths["/api/medications/{medication_id}/daily-status"]["put"]["responses"]["200"]
    reference = response["content"]["application/json"]["schema"]["allOf"][1]["properties"]["data"][
        "$ref"
    ]
    assert reference.endswith("/MedicationDailyMutation")


def test_cycle_delete_and_weight_limits_match_issues() -> None:
    contract = load_contract()

    assert "delete" in contract["paths"]["/api/cycles/{cycle_id}"]
    weight = contract["components"]["schemas"]["WeightInput"]["properties"]["weight_kg"]
    assert weight["minimum"] == 20
    assert weight["maximum"] == 300
    assert weight["multipleOf"] == 0.1


def test_dashboard_exposes_independently_failable_sections() -> None:
    schemas = load_contract()["components"]["schemas"]
    dashboard = schemas["Dashboard"]
    sections = {
        "follow_up",
        "today_medications",
        "monthly_medication_summary",
        "latest_report",
    }

    assert {"business_date", *sections} <= set(dashboard["required"])
    for name in sections:
        reference = dashboard["properties"][name]["$ref"]
        section = schemas[reference.removeprefix("#/components/schemas/")]
        assert section["required"] == ["status", "data", "error"]
        status_reference = section["properties"]["status"]["$ref"]
        assert schemas[status_reference.removeprefix("#/components/schemas/")]["enum"] == [
            "ok",
            "empty",
            "error",
        ]
        error_reference = section["properties"]["error"]["oneOf"][0]["$ref"]
        error = schemas[error_reference.removeprefix("#/components/schemas/")]
        assert error["required"] == ["code", "message", "retryable"]

    assert dashboard["properties"]["latest_report"]["$ref"].endswith(
        "/DashboardLatestReportSection"
    )
    latest = schemas["DashboardLatestReportSection"]["properties"]["data"]["oneOf"][0]
    assert latest["$ref"].endswith("/ReportListItem")


def test_patient_note_workflow_contract_matches_issue_27() -> None:
    contract = load_contract()
    paths = contract["paths"]

    assert "post" in paths["/api/patient-notes"]
    assert "get" in paths["/api/patient-notes/latest"]
    assert "put" in paths["/api/patient-notes/{note_id}"]
    for action in ("confirm", "skip", "copy"):
        assert "post" in paths[f"/api/patient-notes/{{note_id}}/{action}"]

    schemas = contract["components"]["schemas"]
    statuses = schemas["PatientNoteStatus"]["enum"]
    assert statuses == ["draft", "confirmed", "skipped", "consumed"]
    assert schemas["PatientNoteInput"]["additionalProperties"] is False
    assert set(schemas["PatientNoteInput"]["properties"]) == {
        "original_text",
        "visit_context",
    }
    assert {"confirmed_by_uid", "source_note_id", "consumed_at"} <= set(
        schemas["PatientNote"]["properties"]
    )
    copy = paths["/api/patient-notes/{note_id}/copy"]["post"]
    assert copy["requestBody"]["required"] is True


def test_ocr_contract_matches_worker_status_and_material_schemas() -> None:
    contract = load_contract()
    paths = contract["paths"]
    schemas = contract["components"]["schemas"]

    assert paths["/api/ocr/tasks"]["post"]["responses"].get("201") is not None
    assert paths["/api/ocr/tasks/{task_id}/retry"]["post"]["responses"].get("201") is not None
    assert schemas["OcrTaskStatus"]["enum"] == [
        "queued",
        "processing",
        "pending_confirmation",
        "confirmed",
        "failed",
        "timed_out",
    ]
    assert schemas["OcrResultSource"]["enum"] == ["qwen3-vl"]
    field = schemas["OcrFieldResult"]
    assert {"path", "source_text", "parsed_value", "confidence"} <= set(field["required"])
    draft_refs = schemas["OcrDraftResult"]["properties"]["validated_draft"]["oneOf"]
    assert [item["$ref"].rsplit("/", 1)[-1] for item in draft_refs] == [
        "LabDraft",
        "MedicalOrderDraft",
        "ImagingTextDraft",
        "OutpatientRecordDraft",
    ]
    assert set(schemas["LabDraft"]["properties"]) == {
        "hospital_name",
        "sample_date",
        "report_date",
        "items",
    }
    assert "drug_name" in schemas["MedicalOrderItemDraft"]["properties"]


def test_lab_confirmation_contract_matches_runtime_and_traceability() -> None:
    contract = load_contract()
    paths = contract["paths"]
    schemas = contract["components"]["schemas"]

    confirmation = paths["/api/ocr/tasks/{task_id}/confirm"]["post"]
    request_schema = confirmation["requestBody"]["content"]["application/json"]["schema"]
    request_refs = {item["$ref"] for item in request_schema["oneOf"]}
    assert request_refs == {
        "#/components/schemas/LabConfirmRequest",
        "#/components/schemas/ClinicalTextConfirmRequest",
    }
    assert {"401", "404", "409", "422"} <= set(confirmation["responses"])
    assert "Idempotency-Key" not in str(confirmation.get("parameters", []))

    item = schemas["LabConfirmationItem"]
    assert item["additionalProperties"] is False
    assert {"source_index", "name", "value", "unit", "reference_range"} <= set(item["properties"])
    assert schemas["FieldConfirmationStatus"]["enum"] == [
        "pending",
        "confirmed",
        "edited",
        "rejected",
    ]
    assert "source_document" in schemas["OcrDraftResult"]["properties"]
    assert "get" in paths["/api/lab-observations"]
    assert "get" in paths["/api/lab-observations/{observation_id}"]
    observation = schemas["LabObservation"]
    assert {
        "document_revision_id",
        "ocr_result_id",
        "original_item_data",
        "confirmed_item_data",
        "confirmed_by_uid",
    } <= set(observation["required"])


def test_clinical_text_confirmation_contract_uses_worker_draft_fields() -> None:
    schemas = load_contract()["components"]["schemas"]
    imaging = schemas["ImagingTextConfirmation"]
    outpatient = schemas["OutpatientRecordConfirmation"]

    assert set(imaging["required"]) == {"findings_text", "conclusion_text"}
    assert {"examination_method", "examined_at", "reported_at"} <= set(imaging["properties"])
    assert {"visit_date", "diagnosis_summary", "medical_advice"} == set(outpatient["required"])
    assert {"hospital_name", "department_name"} <= set(outpatient["properties"])
    assert schemas["ClinicalFieldConfirmation"]["properties"]["confirmation_status"]["enum"] == [
        "confirmed",
        "edited",
        "rejected",
    ]
