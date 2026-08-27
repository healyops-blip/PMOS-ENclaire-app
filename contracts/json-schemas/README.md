# JSON schemas

Shared payload schemas and enumerations belong here so the Flutter client, API,
and worker can validate the same contracts.

P0 API-facing fields remain defined under `components.schemas` in
[`../openapi/pomi-api-v1.yaml`](../openapi/pomi-api-v1.yaml). The Qwen3-VL and
mock adapters validate provider output against the four standalone Draft 2020-12
schemas in this directory before any result can be shown or confirmed.
