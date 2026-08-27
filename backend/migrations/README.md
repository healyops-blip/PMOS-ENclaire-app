# Database migrations

Alembic owns all backend schema changes. The default database is SQLite, while
the schema avoids SQLite-only column types so it can later migrate to PostgreSQL.

From the `backend` directory:

```bash
python -m alembic upgrade head
python -m alembic current
```

Override the local database without changing tracked files:

```bash
POMI_DATABASE_URL=sqlite:////absolute/path/pomi.db python -m alembic upgrade head
```

Runtime database files must not be committed.
