from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.features.volunteers.model import VolunteerApplicationStatus


class VolunteerApplicationCreate(BaseModel):
    municipality_id: int = Field(gt=0)

    model_config = ConfigDict(extra="forbid")


class MunicipalitySummary(BaseModel):
    id: int
    name: str
    latitude: Decimal
    longitude: Decimal
    is_active: bool

    model_config = ConfigDict(from_attributes=True)


class ApplicantResponse(BaseModel):
    id: int
    full_name: str
    phone: str
    national_id: str
    birth_date: date

    model_config = ConfigDict(from_attributes=True)


class UserVolunteerApplicationResponse(BaseModel):
    id: int
    status: VolunteerApplicationStatus
    municipality: MunicipalitySummary
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MunicipalityVolunteerApplicationResponse(BaseModel):
    id: int
    status: VolunteerApplicationStatus
    user: ApplicantResponse
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class UserApplicationListParams(BaseModel):
    page: int = Field(default=1, ge=1)
    limit: int = Field(default=20, ge=1, le=100)


class MunicipalityApplicationListParams(UserApplicationListParams):
    status: VolunteerApplicationStatus | None = None
    search: str | None = Field(default=None, max_length=255)

    @field_validator("search")
    @classmethod
    def normalize_search(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split())
        return normalized or None


class UserVolunteerApplicationListResponse(BaseModel):
    items: list[UserVolunteerApplicationResponse]
    page: int
    limit: int
    total: int


class MunicipalityVolunteerApplicationListResponse(BaseModel):
    items: list[MunicipalityVolunteerApplicationResponse]
    page: int
    limit: int
    total: int


class VolunteerMeResponse(BaseModel):
    id: int
    user_id: int
    municipality: MunicipalitySummary
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MunicipalityVolunteerListItem(BaseModel):
    id: int
    user_id: int
    full_name: str
    phone: str
    national_id: str
    birth_date: date
    created_at: datetime


class MunicipalityVolunteerListParams(BaseModel):
    page: int = Field(default=1, ge=1)
    limit: int = Field(default=20, ge=1, le=100)
    search: str | None = Field(default=None, max_length=255)

    @field_validator("search")
    @classmethod
    def normalize_search(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split())
        return normalized or None


class MunicipalityVolunteerListResponse(BaseModel):
    items: list[MunicipalityVolunteerListItem]
    page: int
    limit: int
    total: int


class AcceptApplicationResponse(BaseModel):
    application: MunicipalityVolunteerApplicationResponse
    volunteer: MunicipalityVolunteerListItem
