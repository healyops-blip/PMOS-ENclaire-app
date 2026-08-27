"""Command-line entrypoint for server-local administrative operations."""

from __future__ import annotations

import argparse
import getpass
import os
from collections.abc import Sequence
from datetime import UTC, datetime

from pomi_backend.admin.accounts import AccountNotFound, reset_password, seed_initial_accounts
from pomi_backend.admin.health_seed import seed_health_data
from pomi_backend.config import Settings
from pomi_backend.db import build_engine, build_session_factory
from pomi_backend.services.security import PasswordManager


def read_secret(environment_name: str, prompt: str) -> str:
    value = os.getenv(environment_name)
    if value is not None:
        return value
    return getpass.getpass(prompt)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pomi-admin", description="Server-local Pomi administrative commands"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser(
        "seed-accounts", help="Idempotently create initial and returning accounts"
    )
    subparsers.add_parser(
        "seed-health", help="Idempotently create synthetic health records for seeded accounts"
    )
    subparsers.add_parser(
        "purge-documents", help="Delete expired, unreferenced document files after retention"
    )
    reset_parser = subparsers.add_parser(
        "reset-password", help="Reset one account password and revoke all Sessions"
    )
    reset_parser.add_argument("account_name")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    settings = Settings.from_env()
    engine = build_engine(settings.database_url)
    session_factory = build_session_factory(engine)
    password_manager = PasswordManager(settings)

    try:
        with session_factory() as session:
            if args.command == "seed-accounts":
                results = seed_initial_accounts(
                    session,
                    password_manager,
                    first_time_account_name=os.getenv(
                        "POMI_FIRST_TIME_ACCOUNT_NAME", "first-time-user"
                    ),
                    first_time_password=read_secret(
                        "POMI_FIRST_TIME_ACCOUNT_PASSWORD", "First-time account password: "
                    ),
                    returning_account_name=os.getenv(
                        "POMI_RETURNING_ACCOUNT_NAME", "returning-user"
                    ),
                    returning_password=read_secret(
                        "POMI_RETURNING_ACCOUNT_PASSWORD", "Returning account password: "
                    ),
                )
                for result in results:
                    action = "created" if result.created else "already exists"
                    print(
                        f"{result.account_name}: {action}; "
                        f"uid={result.uid}; onboarding_completed={result.onboarding_completed}"
                    )
                return 0

            if args.command == "seed-health":
                from pomi_backend.repositories import AuthRepository

                repository = AuthRepository(session)
                first_time = repository.get_account_by_name(
                    os.getenv("POMI_FIRST_TIME_ACCOUNT_NAME", "first-time-user")
                )
                returning = repository.get_account_by_name(
                    os.getenv("POMI_RETURNING_ACCOUNT_NAME", "returning-user")
                )
                if first_time is None or returning is None:
                    raise ValueError("run pomi-admin seed-accounts before seed-health")
                result = seed_health_data(
                    session,
                    new_account_uid=first_time.uid,
                    returning_account_uid=returning.uid,
                )
                print(
                    "Health seed completed; "
                    f"new_patient_id={result.new_patient_id}; "
                    f"returning_patient_id={result.returning_patient_id}; "
                    f"created_rows={result.created_rows}"
                )
                return 0

            if args.command == "purge-documents":
                from pomi_backend.services.documents import purge_deleted_documents

                removed = purge_deleted_documents(
                    session,
                    settings.storage_root,
                    now=datetime.now(UTC),
                )
                print(f"Document cleanup completed; removed_files={removed}")
                return 0

            revoked_count = reset_password(
                session,
                password_manager,
                account_name=args.account_name,
                new_password=read_secret("POMI_RESET_PASSWORD", "New password: "),
            )
            print(f"Password reset completed; revoked_sessions={revoked_count}")
            return 0
    except (AccountNotFound, ValueError) as error:
        print(f"Operation failed: {error}")
        return 2
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
