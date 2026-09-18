from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.security import (
    access_token_lifetime,
    create_token,
    decode_token,
    hash_token,
    refresh_token_lifetime,
    verify_password,
)
from app.db.session import get_db
from app.features.auth.model import UserSession
from app.features.auth.schema import LoginRequest, RefreshTokenRequest
from app.features.users.model import User

USER_ACCOUNT_TYPE = "user"

bearer_scheme = HTTPBearer(auto_error=False)


def authentication_error(detail: str = "Invalid or expired token") -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_user_id_from_token(token: str, token_type: str) -> int | None:
    payload = decode_token(token, expected_token_type=token_type)
    if payload is None or payload.get("account_type") != USER_ACCOUNT_TYPE:
        return None

    try:
        return int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        return None


def create_user_token(user_id: int, token_type: str, lifetime: timedelta) -> str:
    return create_token(
        {
            "sub": str(user_id),
            "account_type": USER_ACCOUNT_TYPE,
        },
        expires_delta=lifetime,
        token_type=token_type,
    )


async def login(db: AsyncSession, login_data: LoginRequest) -> dict[str, str]:
    result = await db.execute(select(User).where(User.phone == login_data.phone))
    user = result.scalar_one_or_none()

    if user is None or not verify_password(login_data.pin, user.pin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid phone or PIN",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive",
        )

    access_token = create_user_token(user.id, "access", access_token_lifetime())
    refresh_lifetime = refresh_token_lifetime()
    refresh_token = create_user_token(user.id, "refresh", refresh_lifetime)

    session = UserSession(
        user_id=user.id,
        refresh_token_hash=hash_token(refresh_token),
        expires_at=datetime.now(timezone.utc) + refresh_lifetime,
    )
    db.add(session)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to create user session",
        ) from None

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


async def refresh_access_token(
    refresh_data: RefreshTokenRequest,
    db: AsyncSession,
) -> dict[str, str]:
    user_id = get_user_id_from_token(refresh_data.refresh_token, "refresh")
    if user_id is None:
        raise authentication_error("Invalid or expired refresh token")

    result = await db.execute(
        select(UserSession)
        .options(selectinload(UserSession.user))
        .where(
            UserSession.refresh_token_hash
            == hash_token(refresh_data.refresh_token)
        )
    )
    session = result.scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if (
        session is None
        or session.user_id != user_id
        or session.revoked_at is not None
        or session.expires_at <= now
    ):
        raise authentication_error("Invalid or expired refresh token")

    if not session.user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive",
        )

    return {
        "access_token": create_user_token(
            user_id,
            "access",
            access_token_lifetime(),
        ),
        "token_type": "bearer",
    }


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Security(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    if credentials is None:
        raise authentication_error("Access token missing")

    user_id = get_user_id_from_token(credentials.credentials, "access")
    if user_id is None:
        raise authentication_error("Invalid or expired access token")

    user = await db.get(User, user_id)
    if user is None:
        raise authentication_error("Invalid or expired access token")

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive",
        )

    return user


async def logout(
    db: AsyncSession,
    refresh_data: RefreshTokenRequest,
) -> dict[str, str]:
    user_id = get_user_id_from_token(refresh_data.refresh_token, "refresh")
    if user_id is None:
        raise authentication_error("Invalid or expired refresh token")

    result = await db.execute(
        select(UserSession).where(
            UserSession.refresh_token_hash
            == hash_token(refresh_data.refresh_token)
        )
    )
    session = result.scalar_one_or_none()

    if (
        session is None
        or session.user_id != user_id
        or session.revoked_at is not None
        or session.expires_at <= datetime.now(timezone.utc)
    ):
        raise authentication_error("Invalid or expired refresh token")

    session.revoked_at = datetime.now(timezone.utc)
    await db.commit()

    return {"message": "Logged out successfully"}
