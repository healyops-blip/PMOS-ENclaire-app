"""Versioned prompts and strict JSON Schemas for supported medical materials."""

from __future__ import annotations

from typing import Any

PROMPT_VERSION = "pomi-ocr-v1"
SCHEMA_VERSION = "pomi-ocr-schema-v1"


def _draft_schema(material_type: str) -> dict[str, Any]:
    schemas: dict[str, dict[str, Any]] = {
        "lab_report": {
            "type": "object",
            "properties": {
                "facility": {"type": ["string", "null"]},
                "report_date": {"type": ["string", "null"]},
                "items": {"type": "array", "items": {"type": "object"}},
            },
            "required": ["items"],
            "additionalProperties": False,
        },
        "medical_order": {
            "type": "object",
            "properties": {
                "facility": {"type": ["string", "null"]},
                "order_date": {"type": ["string", "null"]},
                "medications": {"type": "array", "items": {"type": "object"}},
            },
            "required": ["medications"],
            "additionalProperties": False,
        },
        "imaging_text_report": {
            "type": "object",
            "properties": {
                "facility": {"type": ["string", "null"]},
                "report_date": {"type": ["string", "null"]},
                "modality": {"type": ["string", "null"]},
                "findings": {"type": ["string", "null"]},
                "impression": {"type": ["string", "null"]},
            },
            "required": ["findings", "impression"],
            "additionalProperties": False,
        },
        "outpatient_record": {
            "type": "object",
            "properties": {
                "facility": {"type": ["string", "null"]},
                "department": {"type": ["string", "null"]},
                "visit_date": {"type": ["string", "null"]},
                "chief_complaint": {"type": ["string", "null"]},
                "diagnoses": {"type": "array", "items": {"type": "string"}},
                "plan": {"type": ["string", "null"]},
            },
            "required": ["diagnoses"],
            "additionalProperties": False,
        },
    }
    return schemas[material_type]


def schema_for(material_type: str) -> dict[str, Any]:
    """Return the material-specific extraction envelope schema."""

    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "properties": {
            "draft": _draft_schema(material_type),
            "fields": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "minLength": 1, "maxLength": 300},
                        "source_text": {"type": ["string", "null"]},
                        "value": {},
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                        "uncertainty_reason": {"type": ["string", "null"]},
                        "source_region": {
                            "oneOf": [
                                {"type": "null"},
                                {
                                    "type": "object",
                                    "properties": {
                                        "page": {"type": "integer", "minimum": 1},
                                        "x": {"type": "number", "minimum": 0, "maximum": 1},
                                        "y": {"type": "number", "minimum": 0, "maximum": 1},
                                        "width": {"type": "number", "minimum": 0, "maximum": 1},
                                        "height": {"type": "number", "minimum": 0, "maximum": 1},
                                    },
                                    "required": ["page", "x", "y", "width", "height"],
                                    "additionalProperties": False,
                                },
                            ]
                        },
                    },
                    "required": ["path", "source_text", "value", "confidence"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["draft", "fields"],
        "additionalProperties": False,
    }


def prompt_for(material_type: str) -> str:
    labels = {
        "lab_report": "化验/检验报告",
        "medical_order": "医嘱/处方",
        "imaging_text_report": "影像文字报告",
        "outpatient_record": "门诊病历",
    }
    return (
        f"你是医疗材料文字转录工具。材料类型已由用户确定为{labels[material_type]}。"
        "只转录可见文字，不作诊断、不推测缺失信息。严格按所给 JSON Schema 输出。"
        "draft 保存结构化草稿；fields 为每个叶字段提供 JSON path、原文、解析值、0-1 "
        "置信度、不确定原因和归一化来源区域。看不清时保留 null 并说明原因。"
    )
