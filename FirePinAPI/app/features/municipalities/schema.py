import re
from datetime import datetime
from decimal import Decimal
from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    field_validator,
    model_validator,
)

ARABIC_NAME_PATTERN = re.compile(
    r"^[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff ]+$"
)

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


def normalize_municipality_name(value: str) -> str:
    normalized = " ".join(value.split())
    if not 2 <= len(normalized) <= 255:
        raise ValueError("Municipality name must be between 2 and 255 characters")
    if not ARABIC_NAME_PATTERN.fullmatch(normalized) or not any(
        character.isalpha() for character in normalized
    ):
        raise ValueError("Municipality name must contain Arabic characters only")
    return normalized


def normalize_email(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("Email must be a string")
    return value.strip().lower()


def validate_password(value: str) -> str:
    if len(value) < 8:
        raise ValueError("Password must contain at least 8 characters")
    if len(value.encode("utf-8")) > 72:
        raise ValueError("Password must not exceed 72 bytes")
    return value


class MunicipalityCreate(BaseModel):
    name: str
    email: EmailStr
    password: str
    latitude: Latitude
    longitude: Longitude

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        return normalize_municipality_name(value)

    @field_validator("email", mode="before")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)

    @field_validator("password")
    @classmethod
    def validate_password_value(cls, value: str) -> str:
        return validate_password(value)


class MunicipalityLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email", mode="before")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)

class MunicipalityUpdate(BaseModel):
    name: str | None = None
    email: EmailStr | None = None
    latitude: Latitude | None = None
    longitude: Longitude | None = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return normalize_municipality_name(value)

    @field_validator("email", mode="before")
    @classmethod
    def validate_email(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return normalize_email(value)

    @model_validator(mode="after")
    def require_update_value(self) -> "MunicipalityUpdate":
        if all(
            value is None
            for value in (self.name, self.email, self.latitude, self.longitude)
        ):
            raise ValueError("At least one profile field must be provided")
        return self


class MunicipalityPublicResponse(BaseModel):
    id: int
    name: str
    latitude: Decimal
    longitude: Decimal
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MunicipalityProfileResponse(MunicipalityPublicResponse):
    email: EmailStr


class MunicipalityListParams(BaseModel):
    page: int = Field(default=1, ge=1)
    limit: int = Field(default=20, ge=1, le=100)
    search: str | None = Field(default=None, max_length=255)
    is_active: bool | None = None

    @field_validator("search")
    @classmethod
    def normalize_search(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split())
        return normalized or None


class MunicipalityListResponse(BaseModel):
    items: list[MunicipalityPublicResponse]
    page: int
    limit: int
    total: int
