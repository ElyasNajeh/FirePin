from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class NotificationEvent(Base):
    __tablename__ = "notification_events"
    __table_args__ = (
        CheckConstraint(
            "(recipient_user_id IS NOT NULL AND recipient_municipality_id IS NULL) "
            "OR (recipient_user_id IS NULL AND recipient_municipality_id IS NOT NULL)",
            name="ck_notification_events_one_recipient",
        ),
        Index("ix_notification_events_user_created", "recipient_user_id", "id"),
        Index(
            "ix_notification_events_municipality_created",
            "recipient_municipality_id",
            "id",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    recipient_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True
    )
    recipient_municipality_id: Mapped[int | None] = mapped_column(
        ForeignKey("municipalities.id", ondelete="CASCADE"), nullable=True
    )
    fire_report_id: Mapped[int] = mapped_column(
        ForeignKey("fire_reports.id", ondelete="CASCADE")
    )
    event_type: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(255))
    body: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
