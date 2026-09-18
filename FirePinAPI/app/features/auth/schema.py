from pydantic import BaseModel, Field, field_validator

from app.features.users.schema import normalize_phone, validate_pin_value


class LoginRequest(BaseModel):
    phone: str
    pin: str

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        return normalize_phone(value)

    @field_validator("pin")
    @classmethod
    def validate_pin(cls, value: str) -> str:
        return validate_pin_value(value)


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class RefreshResponse(BaseModel):
    access_token: str
    token_type: str


class MessageResponse(BaseModel):
    message: str
