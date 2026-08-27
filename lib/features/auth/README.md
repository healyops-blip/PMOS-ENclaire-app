# Authentication feature

The user account feature belongs here. Keep it separated into these layers when implementation starts:

```text
auth/
├── data/          # FastAPI DTOs, SessionStore, and repository implementations
├── domain/        # User entities, repository contracts, and business rules
└── presentation/  # Screens, widgets, and state management
```

Initial scope:

- account-name/password sign up, sign in, and sign out
- session restoration
- route to onboarding or Dashboard from `onboarding_completed`
- optional phone number collection without SMS verification

The implemented backend contract is documented in
[`../../../docs/backend-api.md`](../../../docs/backend-api.md). Registration does
not create a session, so the client must call login after a successful register.
Authenticated calls use `Authorization: Bearer <session_id>` and only the opaque
`session_id` is stored in `SecureSessionStore`.

SMS verification, email verification, password recovery, account deletion, and
third-party identity providers are outside the current P0 scope. Do not implement
custom password storage, token signing, or authentication protocols in Flutter.
