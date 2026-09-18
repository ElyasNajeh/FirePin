from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.features.auth.service import get_current_user
from app.features.device_tokens import service
from app.features.device_tokens.model import DeviceToken
from app.features.device_tokens.schema import (
    DeviceTokenCreate,
    DeviceTokenRemove,
    DeviceTokenRemovedResponse,
    DeviceTokenResponse,
)
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import get_current_municipality
from app.features.users.model import User

router = APIRouter(tags=["Device Tokens"])


@router.post(
    "/device-tokens",
    response_model=DeviceTokenResponse,
    status_code=status.HTTP_200_OK,
)
async def register_user_token(
    token_data: DeviceTokenCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DeviceToken:
    return await service.register_token(db, token_data, user_id=user.id)


@router.delete(
    "/device-tokens",
    response_model=DeviceTokenRemovedResponse,
    status_code=status.HTTP_200_OK,
)
async def remove_user_token(
    token_data: DeviceTokenRemove,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    return await service.remove_token(db, token_data.token, user_id=user.id)


@router.post(
    "/municipalities/auth/device-tokens",
    response_model=DeviceTokenResponse,
    status_code=status.HTTP_200_OK,
)
async def register_municipality_token(
    token_data: DeviceTokenCreate,
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> DeviceToken:
    return await service.register_token(
        db,
        token_data,
        municipality_id=municipality.id,
    )


@router.delete(
    "/municipalities/auth/device-tokens",
    response_model=DeviceTokenRemovedResponse,
    status_code=status.HTTP_200_OK,
)
async def remove_municipality_token(
    token_data: DeviceTokenRemove,
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    return await service.remove_token(
        db,
        token_data.token,
        municipality_id=municipality.id,
    )
