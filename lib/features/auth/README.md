# Authentication feature

The user account feature belongs here. Keep it separated into these layers when implementation starts:

```text
auth/
├── data/          # Supabase clients, DTOs, and repository implementations
├── domain/        # User entities, repository contracts, and business rules
└── presentation/  # Screens, widgets, and state management
```

Initial scope:

- sign up, sign in, and sign out
- email verification and password recovery
- session restoration
- profile viewing and editing
- account deletion
- privacy consent records

Do not implement custom password storage, token signing, or authentication protocols.
