# Repository architecture

PMOS ENclaire uses one repository for the Flutter client and its Supabase backend assets.

```text
PMOS-ENclaire-app/
├── lib/
│   ├── core/             # Shared Flutter infrastructure
│   └── features/         # Product features, organized by feature
│       └── auth/         # User and authentication feature
├── test/                 # Flutter unit and widget tests
├── android/              # Android host project
├── ios/                  # iOS host project
├── supabase/
│   ├── migrations/       # PostgreSQL schema and RLS changes
│   └── functions/        # Privileged server-side functions
├── docs/                 # Architecture, API, privacy, and decisions
└── .github/workflows/    # Required repository checks
```

## Boundaries

- Flutter owns presentation, local state, validation, and calls to approved APIs.
- Supabase Auth owns credentials and sessions; the app never stores passwords itself.
- PostgreSQL plus Row Level Security owns data authorization.
- Edge Functions own privileged operations and third-party secrets.
- Product business modules are added under `lib/features/` only after their requirements are agreed.

## Change process

All changes go through a pull request, one approval, and the required repository checks. Schema changes and access policies must be reviewed together.
