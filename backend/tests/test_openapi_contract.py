from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from pomi_backend.main import app

HTTP_METHODS = {"get", "post", "put", "patch", "delete"}


def _resolve(specification: dict[str, Any], value: dict[str, Any]) -> dict[str, Any]:
    reference = value.get("$ref")
    if not reference:
        return value
    resolved: Any = specification
    for part in reference.removeprefix("#/").split("/"):
        resolved = resolved[part.replace("~1", "/").replace("~0", "~")]
    return resolved


def _parameters(specification: dict[str, Any], operation: dict[str, Any]) -> list[tuple]:
    return [
        (
            parameter["name"],
            parameter["in"],
            parameter.get("required", False),
        )
        for raw_parameter in operation.get("parameters", [])
        for parameter in [_resolve(specification, raw_parameter)]
    ]


def test_fastapi_paths_methods_and_parameters_match_contract() -> None:
    contract_path = Path(__file__).resolve().parents[2] / "contracts/openapi/pomi-api-v1.yaml"
    specification = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
    generated = app.openapi()

    expected_operations = {
        (path, method)
        for path, path_item in specification["paths"].items()
        for method in path_item
        if method in HTTP_METHODS
    }
    generated_operations = {
        (path, method)
        for path, path_item in generated["paths"].items()
        for method in path_item
        if method in HTTP_METHODS
    }
    assert generated_operations == expected_operations

    for path, method in expected_operations:
        expected = specification["paths"][path][method]
        actual = generated["paths"][path][method]
        assert _parameters(specification, actual) == _parameters(specification, expected), (
            method,
            path,
        )
