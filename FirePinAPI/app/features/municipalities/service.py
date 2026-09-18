from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.security import (
    access_token_lifetime,
    create_token,
    decode_token,
    hash_password,
    hash_token,
    refresh_token_lifetime,
    verify_password,
)
from app.db.session import get_db
from app.features.auth.schema import RefreshTokenRequest
from app.features.municipalities.model import Municipality, MunicipalitySession
from app.features.municipalities.schema import (
    MunicipalityCreate,
    MunicipalityListParams,
    MunicipalityLoginRequest,
    MunicipalityUpdate,
)

MUNICIPALITY_ACCOUNT_TYPE = "municipality"

bearer_scheme = HTTPBearer(auto_error=False)


def authentication_error(detail: str = "Invalid or expired token") -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_municipality_id_from_token(token: str, token_type: str) -> int | None:
    payload = decode_token(token, expected_token_type=token_type)
    if (
        payload is None
        or payload.get("account_type") != MUNICIPALITY_ACCOUNT_TYPE
    ):
        return None

    try:
        return int(payload["sub"])
    except (KeyError, TypeError, ValueError):
        return None


def create_municipality_token(
    municipality_id: int,
    token_type: str,
    lifetime: timedelta,
) -> str:
    return create_token(
        {
            "sub": str(municipality_id),
            "account_type": MUNICIPALITY_ACCOUNT_TYPE,
        },
        expires_delta=lifetime,
        token_type=token_type,
    )


async def create_municipality(
    db: AsyncSession,
    municipality_data: MunicipalityCreate,
) -> Municipality:
    name_result = await db.execute(
        select(Municipality.id).where(
            Municipality.name == municipality_data.name
        )
    )
    if name_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Municipality name already exists",
        )

    email = str(municipality_data.email)
    email_result = await db.execute(
        select(Municipality.id).where(Municipality.email == email)
    )
    if email_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Municipality email already exists",
        )

    municipality = Municipality(
        name=municipality_data.name,
        email=email,
        password_hash=hash_password(municipality_data.password),
        latitude=municipality_data.latitude,
        longitude=municipality_data.longitude,
    )
    db.add(municipality)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Municipality name or email already exists",
        ) from None

    await db.refresh(municipality)
    return municipality


async def login(
    db: AsyncSession,
    login_data: MunicipalityLoginRequest,
) -> dict[str, str]:
    result = await db.execute(
        select(Municipality).where(
            Municipality.email == str(login_data.email)
        )
    )
    municipality = result.scalar_one_or_none()

    if municipality is None or not verify_password(
        login_data.password,
        municipality.password_hash,
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not municipality.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive",
        )

    access_token = create_municipality_token(
        municipality.id,
        "access",
        access_token_lifetime(),
    )
    refresh_lifetime = refresh_token_lifetime()
    refresh_token = create_municipality_token(
        municipality.id,
        "refresh",
        refresh_lifetime,
    )

    session = MunicipalitySession(
        municipality_id=municipality.id,
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
            detail="Unable to create municipality session",
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
    municipality_id = get_municipality_id_from_token(
        refresh_data.refresh_token,
        "refresh",
    )
    if municipality_id is None:
        raise authentication_error("Invalid or expired refresh token")

    result = await db.execute(
        select(MunicipalitySession)
        .options(selectinload(MunicipalitySession.municipality))
        .where(
            MunicipalitySession.refresh_token_hash
            == hash_token(refresh_data.refresh_token)
        )
    )
    session = result.scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if (
        session is None
        or session.municipality_id != municipality_id
        or session.revoked_at is not None
        or session.expires_at <= now
    ):
        raise authentication_error("Invalid or expired refresh token")

    if not session.municipality.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive",
        )

    return {
        "access_token": create_municipality_token(
            municipality_id,
            "access",
            access_token_lifetime(),
        ),
        "token_type": "bearer",
    }


async def get_current_municipality(
    credentials: HTTPAuthorizationCredentials | None = Security(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Municipality:
    if credentials is None:
        raise authentication_error("Access token missing")

    municipality_id = get_municipality_id_from_token(
        credentials.credentials,
        "access",
    )
    if municipality_id is None:
        raise authentication_error("Invalid or expired access token")

    municipality = await db.get(Municipality, municipality_id)
    if municipality is None:
        raise authentication_error("Invalid or expired access token")

    if not municipality.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive",
        )

    return municipality


async def logout(
    db: AsyncSession,
    refresh_data: RefreshTokenRequest,
) -> dict[str, str]:
    municipality_id = get_municipality_id_from_token(
        refresh_data.refresh_token,
        "refresh",
    )
    if municipality_id is None:
        raise authentication_error("Invalid or expired refresh token")

    result = await db.execute(
        select(MunicipalitySession).where(
            MunicipalitySession.refresh_token_hash
            == hash_token(refresh_data.refresh_token)
        )
    )
    session = result.scalar_one_or_none()

    if (
        session is None
        or session.municipality_id != municipality_id
        or session.revoked_at is not None
        or session.expires_at <= datetime.now(timezone.utc)
    ):
        raise authentication_error("Invalid or expired refresh token")

    session.revoked_at = datetime.now(timezone.utc)
    await db.commit()

    return {"message": "Logged out successfully"}


async def update_municipality(
    db: AsyncSession,
    municipality: Municipality,
    update_data: MunicipalityUpdate,
) -> Municipality:
    values = update_data.model_dump(exclude_none=True)

    if "name" in values and values["name"] != municipality.name:
        name_result = await db.execute(
            select(Municipality.id).where(
                Municipality.name == values["name"],
                Municipality.id != municipality.id,
            )
        )
        if name_result.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Municipality name already exists",
            )

    if "email" in values:
        values["email"] = str(values["email"])
        if values["email"] != municipality.email:
            email_result = await db.execute(
                select(Municipality.id).where(
                    Municipality.email == values["email"],
                    Municipality.id != municipality.id,
                )
            )
            if email_result.scalar_one_or_none() is not None:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Municipality email already exists",
                )

    for field, value in values.items():
        setattr(municipality, field, value)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Municipality name or email already exists",
        ) from None

    await db.refresh(municipality)
    return municipality


async def get_municipality(
    db: AsyncSession,
    municipality_id: int,
) -> Municipality:
    municipality = await db.get(Municipality, municipality_id)
    if municipality is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Municipality not found",
        )
    return municipality


async def get_municipalities(
    db: AsyncSession,
    params: MunicipalityListParams,
) -> dict:
    filters = []

    if params.search:
        filters.append(Municipality.name.ilike(f"%{params.search}%"))

    if params.is_active is not None:
        filters.append(Municipality.is_active == params.is_active)

    total_result = await db.execute(
        select(func.count(Municipality.id)).where(*filters)
    )
    total = total_result.scalar_one()

    municipalities_result = await db.execute(
        select(Municipality)
        .where(*filters)
        .order_by(Municipality.id)
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(municipalities_result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }
