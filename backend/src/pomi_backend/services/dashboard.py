"""Fault-isolated, patient-owned dashboard aggregation."""

from __future__ import annotations

from collections.abc import Callable
from datetime import date
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    PatientProfile,
    ReportSnapshot,
    UserAccount,
)
from pomi_backend.schemas.dashboard import DashboardSection, DashboardSectionError
from pomi_backend.services.medications import MedicationService, daily_data, medication_data


class DashboardService:
    """Build each section independently so a local query failure stays local."""

    def __init__(self, session: Session, account: UserAccount, business_date: date) -> None:
        self.session = session
        self.account = account
        self.business_date = business_date

    def aggregate(self) -> dict[str, Any]:
        return {
            "business_date": self.business_date.isoformat(),
            "follow_up": self._section("FOLLOW_UP_UNAVAILABLE", self.follow_up),
            "today_medications": self._section(
                "TODAY_MEDICATIONS_UNAVAILABLE", self.today_medications
            ),
            "monthly_medication_summary": self._section(
                "MEDICATION_SUMMARY_UNAVAILABLE", self.monthly_medication_summary
            ),
            "latest_report": self._section("LATEST_REPORT_UNAVAILABLE", self.latest_report),
        }

    def _section(self, code: str, loader: Callable[[], Any]) -> dict[str, Any]:
        try:
            data = loader()
            return DashboardSection(
                status="empty" if data is None or data == [] else "ok",
                data=data,
            ).model_dump(mode="json")
        except Exception:  # A dashboard section must not take down its siblings.
            self.session.rollback()
            return DashboardSection(
                status="error",
                error=DashboardSectionError(
                    code=code,
                    message="This dashboard section is temporarily unavailable.",
                ),
            ).model_dump(mode="json")

    def _profile(self) -> PatientProfile | None:
        return self.session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == self.account.uid)
        )

    def follow_up(self) -> dict[str, Any] | None:
        profile = self._profile()
        if profile is None or profile.next_visit_date is None:
            return None
        next_visit = profile.next_visit_date
        delta = (next_visit - self.business_date).days
        state = "upcoming" if delta > 0 else "due" if delta == 0 else "overdue"
        return {
            "next_visit_date": next_visit.isoformat(),
            "state": state,
            "days_remaining": max(delta, 0),
        }

    def today_medications(self) -> list[dict[str, Any]]:
        profile = self._profile()
        if profile is None:
            return []
        medications = list(
            self.session.scalars(
                select(Medication).where(Medication.patient_id == profile.patient_id)
            )
        )
        tracker = MedicationService(self.session, self.account, self.business_date)
        due = [item for item in medications if tracker._is_expected(item, self.business_date)]
        explicit = {
            record.medication_id: record
            for record in self.session.scalars(
                select(MedicationDaily).where(
                    MedicationDaily.patient_id == profile.patient_id,
                    MedicationDaily.record_date == self.business_date,
                )
            )
        }
        return [
            {
                **medication_data(item),
                "daily": daily_data(
                    item,
                    self.business_date,
                    explicit.get(item.id),
                    editable=True,
                ),
            }
            for item in due
        ]

    def monthly_medication_summary(self) -> dict[str, Any] | None:
        if self._profile() is None:
            return None
        month_start = self.business_date.replace(day=1)
        result = MedicationService(self.session, self.account, self.business_date).daily_range(
            month_start, self.business_date
        )
        return {
            "from": result["from"],
            "to": result["to"],
            "taken": result["taken_count"],
            "missed": result["missed_count"],
            "unrecorded": result["unrecorded_count"],
        }

    def latest_report(self) -> dict[str, Any] | None:
        profile = self._profile()
        if profile is None:
            return None
        report = self.session.scalar(
            select(ReportSnapshot)
            .where(
                ReportSnapshot.patient_id == profile.patient_id,
                ReportSnapshot.report_status == "succeeded",
            )
            .order_by(
                ReportSnapshot.report_generated_at.desc(),
                ReportSnapshot.created_at.desc(),
                ReportSnapshot.id.desc(),
            )
            .limit(1)
        )
        if report is None:
            return None
        return {
            "report_id": report.id,
            "status": report.report_status,
            "generated_at": report.report_generated_at.isoformat(),
            "snapshot_hash": report.snapshot_hash,
        }
