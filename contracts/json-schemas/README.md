# JSON schemas

Shared payload schemas and enumerations belong here so the Flutter client, API,
and worker can validate the same contracts.

P0 API-facing fields and the four OCR draft shapes are currently defined under
`components.schemas` in [`../openapi/pomi-api-v1.yaml`](../openapi/pomi-api-v1.yaml).
When the Qwen3-VL adapter is implemented, export the four provider-output subsets
(`LabDraft`, `MedicalOrderDraft`, `ImagingTextDraft`, and
`OutpatientRecordDraft`) here as standalone JSON Schema files without changing
their public field names.
