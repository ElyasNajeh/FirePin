from datetime import date, datetime
from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from app.features.fire_reports.model import FireReportStatus
from app.features.report_images.schema import ReportImageResponse

Latitude = Annotated[
    Decimal,
    Field(ge=Decimal("-90"), le=Decimal("90"), max_digits=9, decimal_places=6),
]
Longitude = Annotated[
    Decimal,
    Field(
        ge=Decimal("-180"),
        le=Decimal("180"),
        max_digits=9,
        decimal_places=6,
    ),
]


class FireReportCreate(BaseModel):
    latitude: Latitude
    longitude: Longitude

    model_config = ConfigDict(extra="forbid")


class FireReportListParams(BaseModel):
    page: int = Field(default=1, ge=1)
    limit: int = Field(default=20, ge=1, le=100)
    status: FireReportStatus | None = None


class FireReportMunicipalityResponse(BaseModel):
    id: int
    name: str

    model_config = ConfigDict(from_attributes=True)


class VolunteerUserResponse(BaseModel):
    id: int
    full_name: str
    phone: str

    model_config = ConfigDict(from_attributes=True)


class AssignedVolunteerResponse(BaseModel):
    id: int
    user: VolunteerUserResponse

    model_config = ConfigDict(from_attributes=True)


class FireReportResponse(BaseModel):
    id: int
    latitude: Decimal
    longitude: Decimal
    status: FireReportStatus
    reported_at: datetime
    updated_at: datetime
    municipality: FireReportMunicipalityResponse
    assigned_volunteer: AssignedVolunteerResponse | None
    images: list[ReportImageResponse]

    model_config = ConfigDict(from_attributes=True)


class FireReportListResponse(BaseModel):
    items: list[FireReportResponse]
    page: int
    limit: int
    total: int


class ReporterResponse(BaseModel):
    id: int
    full_name: str
    phone: str
    national_id: str
    birth_date: date

    model_config = ConfigDict(from_attributes=True)


class MunicipalityFireReportResponse(FireReportResponse):
    reporter: ReporterResponse


class MunicipalityFireReportListResponse(BaseModel):
    items: list[MunicipalityFireReportResponse]
    page: int
    limit: int
    total: int
