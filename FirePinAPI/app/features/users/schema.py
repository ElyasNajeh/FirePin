import re
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


def normalize_phone(value: str) -> str:
    normalized = re.sub(r"[\s\-()]", "", value)
    if not re.fullmatch(r"\+?[0-9]{8,15}", normalized):
        raise ValueError("Phone must contain 8 to 15 digits")
    return normalized


def validate_pin_value(value: str) -> str:
    if not re.fullmatch(r"[0-9]{4,8}", value):
        raise ValueError("PIN must contain 4 to 8 digits")
    return value


def validate_national_id_value(value: str) -> str:
    normalized = re.sub(r"[\s-]", "", value)
    if not re.fullmatch(r"[0-9]{9}", normalized):
        raise ValueError("National ID must contain exactly 9 digits")
    return normalized


class UserRegister(BaseModel):
    full_name: str
    phone: str
    national_id: str
    birth_date: date
    pin: str

    @field_validator("full_name")
    @classmethod
    def validate_full_name(cls, value: str) -> str:
        normalized = " ".join(value.split())
        if not 2 <= len(normalized) <= 255:
            raise ValueError("Full name must be between 2 and 255 characters")
        return normalized

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        return normalize_phone(value)

    @field_validator("national_id")
    @classmethod
    def validate_national_id(cls, value: str) -> str:
        return validate_national_id_value(value)

    @field_validator("birth_date")
    @classmethod
    def validate_birth_date(cls, value: date) -> date:
        if value > date.today():
            raise ValueError("Birth date cannot be in the future")
        return value

    @field_validator("pin")
    @classmethod
    def validate_pin(cls, value: str) -> str:
        return validate_pin_value(value)


class UserResponse(BaseModel):
    id: int
    full_name: str
    phone: str
    national_id: str
    birth_date: date
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class UserListParams(BaseModel):
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


class UserListResponse(BaseModel):
    items: list[UserResponse]
    page: int
    limit: int
    total: int
