from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, field_validator


class DevicePlatform(StrEnum):
    ANDROID = "android"
    IOS = "ios"


class DeviceTokenCreate(BaseModel):
    token: str
    platform: DevicePlatform

    model_config = ConfigDict(extra="forbid")

    @field_validator("token")
    @classmethod
    def validate_token(cls, value: str) -> str:
        normalized = value.strip()
        if not 1 <= len(normalized) <= 500:
            raise ValueError("Token must be between 1 and 500 characters")
        return normalized

    @field_validator("platform", mode="before")
    @classmethod
    def normalize_platform(cls, value: str) -> str:
        if not isinstance(value, str):
            raise ValueError("Platform must be android or ios")
        return value.strip().lower()


class DeviceTokenRemove(BaseModel):
    token: str

    model_config = ConfigDict(extra="forbid")

    @field_validator("token")
    @classmethod
    def validate_token(cls, value: str) -> str:
        normalized = value.strip()
        if not 1 <= len(normalized) <= 500:
            raise ValueError("Token must be between 1 and 500 characters")
        return normalized


class DeviceTokenResponse(BaseModel):
    id: int
    platform: DevicePlatform
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class DeviceTokenRemovedResponse(BaseModel):
    message: str
