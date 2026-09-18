from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.features.fire_reports.model import FireReport


class ReportImage(Base):
    __tablename__ = "report_images"

    id: Mapped[int] = mapped_column(primary_key=True)
    report_id: Mapped[int] = mapped_column(
        ForeignKey("fire_reports.id", ondelete="CASCADE"),
        index=True,
    )
    image_path: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    report: Mapped[FireReport] = relationship(back_populates="images")

    @property
    def url(self) -> str:
        return f"/fire-reports/{self.report_id}/images/{self.id}"
