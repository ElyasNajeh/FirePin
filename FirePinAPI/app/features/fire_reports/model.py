from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.features.municipalities.model import Municipality
from app.features.users.model import User
from app.features.volunteers.model import Volunteer

if TYPE_CHECKING:
    from app.features.report_images.model import ReportImage


class FireReportStatus(StrEnum):
    PENDING = "pending"
    ASSIGNED = "assigned"
    RESOLVED = "resolved"


class FireReport(Base):
    __tablename__ = "fire_reports"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'assigned', 'resolved')",
            name="ck_fire_reports_status",
        ),
        CheckConstraint(
            "(status = 'pending' AND assigned_volunteer_id IS NULL) OR "
            "(status IN ('assigned', 'resolved') "
            "AND assigned_volunteer_id IS NOT NULL)",
            name="ck_fire_reports_assignment_state",
        ),
        Index("ix_fire_reports_reporter_status", "reporter_id", "status"),
        Index(
            "ix_fire_reports_municipality_status",
            "municipality_id",
            "status",
        ),
        Index(
            "ix_fire_reports_assigned_volunteer_id",
            "assigned_volunteer_id",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    reporter_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    municipality_id: Mapped[int] = mapped_column(ForeignKey("municipalities.id"))
    assigned_volunteer_id: Mapped[int | None] = mapped_column(
        ForeignKey("volunteers.id"),
        nullable=True,
    )
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    status: Mapped[str] = mapped_column(
        String(20),
        default=FireReportStatus.PENDING.value,
        server_default=FireReportStatus.PENDING.value,
    )
    reported_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    reporter: Mapped[User] = relationship(back_populates="fire_reports")
    municipality: Mapped[Municipality] = relationship(back_populates="fire_reports")
    assigned_volunteer: Mapped[Volunteer | None] = relationship(
        back_populates="assigned_fire_reports"
    )
    images: Mapped[list["ReportImage"]] = relationship(
        back_populates="report",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="ReportImage.id",
    )
