from datetime import datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, Numeric, String, func, true
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.features.device_tokens.model import DeviceToken
    from app.features.fire_reports.model import FireReport
    from app.features.volunteers.model import Volunteer, VolunteerApplication


class Municipality(Base):
    __tablename__ = "municipalities"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        server_default=true(),
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
    sessions: Mapped[list["MunicipalitySession"]] = relationship(
        back_populates="municipality",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    device_tokens: Mapped[list["DeviceToken"]] = relationship(
        back_populates="municipality",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    volunteer_applications: Mapped[list["VolunteerApplication"]] = relationship(
        back_populates="municipality",
        passive_deletes=True,
    )
    volunteers: Mapped[list["Volunteer"]] = relationship(
        back_populates="municipality",
        passive_deletes=True,
    )
    fire_reports: Mapped[list["FireReport"]] = relationship(
        back_populates="municipality",
        passive_deletes=True,
    )


class MunicipalitySession(Base):
    __tablename__ = "municipality_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    municipality_id: Mapped[int] = mapped_column(
        ForeignKey("municipalities.id", ondelete="CASCADE"),
        index=True,
    )
    refresh_token_hash: Mapped[str] = mapped_column(
        String(64),
        unique=True,
        index=True,
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    municipality: Mapped[Municipality] = relationship(back_populates="sessions")
