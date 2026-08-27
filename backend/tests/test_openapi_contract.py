from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPOSITORY_ROOT / "contracts/openapi/pomi-api-v1.yaml"


def load_contract() -> dict[str, Any]:
    contract = yaml.safe_load(OPENAPI_PATH.read_text(encoding="utf-8"))
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

    assert schemas["MedicationStatus"]["enum"] == ["active", "paused", "stopped", "unknown"]
    assert schemas["MedicationEventType"]["enum"] == [
        "started",
        "adjusted",
        "paused",
        "resumed",
        "stopped",
    ]
    medication_properties = schemas["Medication"]["allOf"][1]["properties"]
    assert medication_properties["replaces_medication_id"]["format"] == "uuid"


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

    assert sections <= set(dashboard["required"])
    for name in sections:
        reference = dashboard["properties"][name]["$ref"]
        section = schemas[reference.removeprefix("#/components/schemas/")]
        assert section["required"] == ["status", "data", "error_code"]


def test_patient_note_workflow_contract_matches_issue_27() -> None:
    contract = load_contract()
    paths = contract["paths"]

    assert "post" in paths["/api/patient-notes"]
    assert "get" in paths["/api/patient-notes/latest"]
    assert "put" in paths["/api/patient-notes/{note_id}"]
    for action in ("confirm", "skip", "copy"):
        assert "post" in paths[f"/api/patient-notes/{{note_id}}/{action}"]

    statuses = contract["components"]["schemas"]["PatientNoteStatus"]["enum"]
    assert statuses == ["draft", "confirmed", "skipped", "consumed"]
