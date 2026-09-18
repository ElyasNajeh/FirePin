from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.features.auth.schema import (
    LoginResponse,
    MessageResponse,
    RefreshResponse,
    RefreshTokenRequest,
)
from app.features.municipalities import service
from app.features.municipalities.model import Municipality
from app.features.municipalities.schema import (
    MunicipalityListParams,
    MunicipalityListResponse,
    MunicipalityLoginRequest,
    MunicipalityProfileResponse,
    MunicipalityPublicResponse,
    MunicipalityUpdate,
)

router = APIRouter(
    prefix="/municipalities",
    tags=["Municipalities"],
)


@router.post(
    "/auth/login",
    response_model=LoginResponse,
    status_code=status.HTTP_200_OK,
)
async def login(
    login_data: MunicipalityLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    return await service.login(db, login_data)


@router.post(
    "/auth/refresh",
    response_model=RefreshResponse,
    status_code=status.HTTP_200_OK,
)
async def refresh_access_token(
    refresh_data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    return await service.refresh_access_token(refresh_data, db)


@router.post(
    "/auth/logout",
    response_model=MessageResponse,
    status_code=status.HTTP_200_OK,
)
async def logout(
    refresh_data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    return await service.logout(db, refresh_data)


@router.get(
    "/auth/me",
    response_model=MunicipalityProfileResponse,
    status_code=status.HTTP_200_OK,
)
async def get_me(
    municipality: Municipality = Depends(service.get_current_municipality),
) -> Municipality:
    return municipality


@router.patch(
    "/auth/me",
    response_model=MunicipalityProfileResponse,
    status_code=status.HTTP_200_OK,
)
async def update_me(
    update_data: MunicipalityUpdate,
    municipality: Municipality = Depends(service.get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> Municipality:
    return await service.update_municipality(db, municipality, update_data)


@router.get(
    "",
    response_model=MunicipalityListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_municipalities(
    params: Annotated[MunicipalityListParams, Query()],
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_municipalities(db, params)


@router.get(
    "/{municipality_id}",
    response_model=MunicipalityPublicResponse,
    status_code=status.HTTP_200_OK,
)
async def get_municipality(
    municipality_id: Annotated[int, Path(gt=0)],
    db: AsyncSession = Depends(get_db),
) -> Municipality:
    return await service.get_municipality(db, municipality_id)
