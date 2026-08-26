# Supabase backend

This directory is the backend boundary for the mobile app.

```text
supabase/
├── migrations/  # Versioned PostgreSQL schema and Row Level Security changes
└── functions/   # Server-side Edge Functions for privileged operations
```

Rules:

- Every application table containing user data must enable Row Level Security.
- Database changes must be committed as migrations and reviewed in a pull request.
- Flutter may use only a Supabase publishable key.
- Never commit secret keys, service-role keys, access tokens, or production credentials.
- Privileged operations belong in authenticated Edge Functions, not in Flutter.

The directory is intentionally not linked to a Supabase project yet.
