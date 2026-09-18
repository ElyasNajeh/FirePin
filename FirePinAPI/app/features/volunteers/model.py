from datetime import datetime
from enum import StrEnum
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    String,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.features.municipalities.model import Municipality
from app.features.users.model import User

if TYPE_CHECKING:
    from app.features.fire_reports.model import FireReport


class VolunteerApplicationStatus(StrEnum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"


class VolunteerApplication(Base):
    __tablename__ = "volunteer_applications"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'accepted', 'rejected')",
            name="ck_volunteer_applications_status",
        ),
        Index("ix_volunteer_applications_user_id", "user_id"),
        Index(
            "ix_volunteer_applications_municipality_status",
            "municipality_id",
            "status",
        ),
        Index(
            "uq_volunteer_applications_user_pending",
            "user_id",
            unique=True,
            postgresql_where=text("status = 'pending'"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    municipality_id: Mapped[int] = mapped_column(ForeignKey("municipalities.id"))
    status: Mapped[str] = mapped_column(
        String(20),
        default=VolunteerApplicationStatus.PENDING.value,
        server_default=VolunteerApplicationStatus.PENDING.value,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    user: Mapped[User] = relationship(back_populates="volunteer_applications")
    municipality: Mapped[Municipality] = relationship(
        back_populates="volunteer_applications"
    )


class Volunteer(Base):
    __tablename__ = "volunteers"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        unique=True,
        index=True,
    )
    municipality_id: Mapped[int] = mapped_column(
        ForeignKey("municipalities.id"),
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    user: Mapped[User] = relationship(back_populates="volunteer")
    municipality: Mapped[Municipality] = relationship(back_populates="volunteers")
    assigned_fire_reports: Mapped[list["FireReport"]] = relationship(
        back_populates="assigned_volunteer",
        passive_deletes=True,
    )
