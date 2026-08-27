# Authentication deployment validation

Validation date: 2026-08-26

## Verified locally

- Ruff passes for the backend source and tests.
- All 24 backend tests pass with warnings treated as errors.
- Alembic upgrades a new SQLite database to `20260826_0001 (head)`.
- The `pomi-admin` entrypoint exposes only `seed-accounts` and
  `reset-password`.
- The SQLite backup script passes Bash syntax validation.
- Backend modules, tests, and the HTTPS authentication smoke script compile.
- Git whitespace validation passes.

The automated tests cover idempotent logout, revoked-session rejection,
idempotent initial-account seeding, onboarding state, password-reset session
revocation, health checks, production host validation, security headers,
database persistence, and static deployment guardrails.

## Must be verified on the Ubuntu server

The following checks depend on the actual server, DNS, certificate, and reboot,
so they are not recorded as passed by local tests:

- `nginx -t` against the installed Nginx version and live certificate paths.
- `systemd-analyze verify` for the installed service and timer units.
- `logrotate --debug` for the installed rule.
- Public DNS resolution and TLS validation for `api.healy1012-ops.top`.
- HTTPS readiness and the destructive authentication smoke script.
- A real SQLite backup followed by checksum and integrity verification.
- Automatic API and backup-timer recovery after a controlled server reboot.

Run and retain the commands in `deploy/README.md` during deployment. Do not mark
the server-dependent acceptance items complete until their output is attached
to the release or issue record.
