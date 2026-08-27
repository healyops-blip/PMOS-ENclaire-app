# OpenAPI contract

The P0 contract is [`pomi-api-v1.yaml`](pomi-api-v1.yaml). It is the machine-readable
source of truth for FastAPI request/response schemas, Flutter DTOs, mocks, and
contract tests.

Development rules:

- Read [`../../docs/frontend-backend-integration.md`](../../docs/frontend-backend-integration.md)
  before implementing a module, and use [`../../docs/backend-api.md`](../../docs/backend-api.md)
  for the already implemented authentication behavior.
- Keep business routes under `/api`; `/health/live` and `/health/ready` are the
  only root-path exceptions. The contract version is `0.1.x` until P0 is frozen.
- The implemented authentication routes use direct response objects. Other
  planned business routes use the documented `ApiSuccess`/`ApiError` envelope.
- Change the OpenAPI file before changing a route or JSON field.
- Regenerate or update FastAPI Pydantic schemas and Flutter DTOs in the same PR.
- Hospital certification, doctor KYC, signing, and blockchain routes are
  intentionally absent from P0.

The file can be imported directly into Swagger Editor, Apifox, Postman, or an
OpenAPI code generator.
