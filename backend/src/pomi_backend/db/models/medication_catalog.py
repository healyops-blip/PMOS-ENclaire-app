"""Versioned, reviewable medication candidates used for recognition and entry."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from pomi_backend.db.base import Base
from pomi_backend.db.models.auth import utc_now
from pomi_backend.db.types import UTCDateTime


class MedicationCatalogEntry(Base):
    """A static candidate; it never represents a patient's actual regimen."""

    __tablename__ = "medication_catalog"
    __table_args__ = (
        Index("ix_medication_catalog_name", "name"),
        Index("ix_medication_catalog_category", "category"),
    )

    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    source: Mapped[str] = mapped_column(String(200), nullable=False)
    disclaimer: Mapped[str] = mapped_column(Text, nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    category: Mapped[str] = mapped_column(String(80), nullable=False)
    item_type: Mapped[str] = mapped_column(String(40), nullable=False)
    pcos_context: Mapped[str] = mapped_column(String(40), nullable=False)
    dosage_forms: Mapped[list[str]] = mapped_column(JSON, nullable=False)
    strength_candidates: Mapped[list[str]] = mapped_column(JSON, nullable=False)
    aliases: Mapped[list[str]] = mapped_column(JSON, nullable=False)
    route: Mapped[str] = mapped_column(String(120), nullable=False)
    usage_reference: Mapped[str] = mapped_column(Text, nullable=False)
    schedule_source: Mapped[str] = mapped_column(String(160), nullable=False)
    user_editable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    can_prefill_reminder: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    review_status: Mapped[str] = mapped_column(String(160), nullable=False)
    record_status: Mapped[str] = mapped_column(String(80), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utc_now, onupdate=utc_now
    )
