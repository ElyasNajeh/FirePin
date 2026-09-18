from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Date, DateTime, String, func, true
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.features.auth.model import UserSession
    from app.features.device_tokens.model import DeviceToken
    from app.features.fire_reports.model import FireReport
    from app.features.volunteers.model import Volunteer, VolunteerApplication


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    full_name: Mapped[str] = mapped_column(String(255))
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    national_id: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    birth_date: Mapped[date] = mapped_column(Date)
    pin_hash: Mapped[str] = mapped_column(String(255))
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
    sessions: Mapped[list["UserSession"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    device_tokens: Mapped[list["DeviceToken"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    volunteer_applications: Mapped[list["VolunteerApplication"]] = relationship(
        back_populates="user",
        passive_deletes=True,
    )
    volunteer: Mapped["Volunteer | None"] = relationship(
        back_populates="user",
        passive_deletes=True,
    )
    fire_reports: Mapped[list["FireReport"]] = relationship(
        back_populates="reporter",
        passive_deletes=True,
    )
