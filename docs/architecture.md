# Repository architecture

PMOS ENclaire uses one repository for the Flutter client, FastAPI backend, SQLite
migrations, and OCR worker. The Flutter project remains at the repository root
to avoid disrupting the generated Android and iOS projects.

```text
PMOS-ENclaire-app/
├── lib/
│   ├── core/             # Shared Flutter infrastructure
│   └── features/         # Product features, organized by feature
│       └── auth/         # User and authentication feature
├── test/                 # Flutter unit and widget tests
├── android/              # Android host project
├── ios/                  # iOS host project
├── backend/
│   ├── src/pomi_backend/
│   │   ├── db/           # SQLAlchemy engine and persistence models
│   │   └── repositories/ # Data-access boundaries
│   ├── migrations/       # Versioned SQLite schema changes
│   ├── worker/           # Single-process OCR worker
│   └── tests/            # Backend tests
├── contracts/
│   ├── openapi/          # Versioned API contract
│   └── json-schemas/     # Shared payload schemas and enums
├── deploy/
│   ├── nginx/            # HTTPS reverse-proxy templates
│   └── systemd/          # API and worker service templates
├── docs/                 # Architecture, API, privacy, and decisions
└── .github/workflows/    # Required repository checks
```

## Boundaries

- Flutter owns presentation, local state, validation, and calls to approved APIs.
- FastAPI owns authentication, authorization, business APIs, PDF generation, and
  calls to external services.
- SQLite owns application data, sessions, task state, and file metadata. Schema
  changes are committed as migrations.
- The OCR worker processes queued jobs outside the API request lifecycle.
- Uploaded medical files live in a private server directory and are accessed only
  after session and user authorization checks.
- Passwords are stored only as Argon2 or bcrypt hashes. Session identifiers are
  random, expire by default after seven days, and are stored as hashes.
- Third-party API keys and production credentials live only in server environment
  variables and are never committed or shipped in the Flutter application.
- Product business modules are added under `lib/features/` only after their requirements are agreed.

## Runtime data

The repository contains migrations and deployment templates, not production data.
SQLite database files, private uploads, generated reports, logs, backups, and
environment files must remain outside Git and be covered by backup and retention
policies on the server.

## Change process

All changes go through a pull request, one approval, and the required repository
checks. Schema changes and their authorization impact must be reviewed together.
