"""Shared validation for OCR provider payloads."""

from __future__ import annotations

from typing import Any

from jsonschema import FormatChecker, ValidationError, validate

from pomi_backend.services.ocr_prompts import schema_for


def validate_provider_payload(
    material_type: str,
    payload: dict[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Validate, normalize, and cross-check a provider extraction envelope."""

    validate(
        instance=payload,
        schema=schema_for(material_type),
        format_checker=FormatChecker(),
    )
    cleaned = _clean(payload)
    draft = cleaned["draft"]
    fields = cleaned["fields"]
    _validate_field_evidence(draft, fields)
    return draft, fields


def _clean(value: Any) -> Any:
    if isinstance(value, str):
        return " ".join(value.split())
    if isinstance(value, list):
        return [_clean(item) for item in value]
    if isinstance(value, dict):
        return {key: _clean(item) for key, item in value.items()}
    return value


def _validate_field_evidence(draft: dict[str, Any], fields: list[dict[str, Any]]) -> None:
    paths: set[tuple[str, ...]] = set()
    for field in fields:
        try:
            parts = _draft_path_parts(field["path"])
            if parts in paths:
                raise ValidationError("field paths must be unique")
            paths.add(parts)
            resolved = _resolve_draft_path(draft, parts)
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise ValidationError("field path does not exist in draft") from exc
        if resolved != field.get("value"):
            raise ValidationError("field evidence value does not match draft")
    if paths != _draft_leaf_paths(draft):
        raise ValidationError("field evidence must cover every draft leaf")


def _draft_path_parts(path: str) -> tuple[str, ...]:
    normalized = path.strip()
    if normalized.startswith("$"):
        normalized = normalized[1:]
    normalized = normalized.lstrip(".")
    if not normalized:
        raise ValueError("empty draft path")
    normalized = normalized.replace("[", ".").replace("]", "")
    parts = normalized.split(".")
    if any(not part for part in parts):
        raise ValueError("invalid draft path")
    return tuple(parts)


def _resolve_draft_path(draft: dict[str, Any], parts: tuple[str, ...]) -> Any:
    current: Any = draft
    for part in parts:
        if isinstance(current, dict):
            current = current[part]
        elif isinstance(current, list):
            current = current[int(part)]
        else:
            raise TypeError("path continues beyond a leaf")
    return current


def _draft_leaf_paths(value: Any, prefix: tuple[str, ...] = ()) -> set[tuple[str, ...]]:
    if isinstance(value, dict):
        return {
            path
            for key, child in value.items()
            for path in _draft_leaf_paths(child, (*prefix, key))
        }
    if isinstance(value, list):
        return {
            path
            for index, child in enumerate(value)
            for path in _draft_leaf_paths(child, (*prefix, str(index)))
        }
    return {prefix}
