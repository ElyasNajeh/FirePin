from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.features.auth.service import get_current_user
from app.features.users import service
from app.features.users.model import User
from app.features.users.schema import (
    UserListParams,
    UserListResponse,
    UserRegister,
    UserResponse,
)

router = APIRouter(
    prefix="/users",
    tags=["Users"],
)


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
)
async def register_user(
    user_data: UserRegister,
    db: AsyncSession = Depends(get_db),
) -> User:
    return await service.register_user(db, user_data)


@router.get(
    "",
    response_model=UserListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_users(
    params: Annotated[UserListParams, Query()],
    _current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_users(db, params)


@router.get(
    "/{user_id}",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
)
async def get_user(
    user_id: Annotated[int, Path(gt=0)],
    _current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    return await service.get_user(db, user_id)
