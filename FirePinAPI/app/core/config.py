from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


class Settings(BaseSettings):
    APP_NAME: str

    DATABASE_HOST: str
    DATABASE_PORT: int
    DATABASE_USER: str
    DATABASE_PASSWORD: str
    DATABASE_NAME: str

    CORS_ORIGINS: str = "*"

    SECRET_KEY: str = Field(min_length=32)
    ALGORITHM: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(gt=0)
    REFRESH_TOKEN_EXPIRE_DAYS: int = Field(gt=0)

    UPLOAD_ROOT: Path
    FIREBASE_CREDENTIALS_PATH: Path | None = None
    VALHALLA_BASE_URL: str = "http://valhalla:8002"
    VALHALLA_TIMEOUT_SECONDS: float = Field(default=10, gt=0)

    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def DATABASE_URL(self) -> str:
        return URL.create(
            drivername="postgresql+asyncpg",
            username=self.DATABASE_USER,
            password=self.DATABASE_PASSWORD,
            host=self.DATABASE_HOST,
            port=self.DATABASE_PORT,
            database=self.DATABASE_NAME,
        ).render_as_string(hide_password=False)

    @property
    def cors_origins(self) -> list[str]:
        return [
            origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()
        ]

    @field_validator("FIREBASE_CREDENTIALS_PATH", mode="before")
    @classmethod
    def empty_firebase_path_is_none(cls, value: str | None) -> str | None:
        if value is None or not str(value).strip():
            return None
        return value


settings = Settings()
