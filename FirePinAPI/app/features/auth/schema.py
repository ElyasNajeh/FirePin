from pydantic import BaseModel, Field, field_validator

from app.features.users.schema import validate_national_id_value, validate_pin_value


class LoginRequest(BaseModel):
    national_id: str
    pin: str

    @field_validator("national_id")
    @classmethod
    def validate_national_id(cls, value: str) -> str:
        return validate_national_id_value(value)

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
