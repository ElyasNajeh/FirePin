import re

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.features.users.model import User
from app.features.users.schema import UserListParams, UserRegister


async def register_user(db: AsyncSession, user_data: UserRegister) -> User:
    phone_result = await db.execute(
        select(User.id).where(User.phone == user_data.phone)
    )
    if phone_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Phone number is already registered",
        )

    national_id_result = await db.execute(
        select(User.id).where(User.national_id == user_data.national_id)
    )
    if national_id_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="National ID is already registered",
        )

    user = User(
        full_name=user_data.full_name,
        phone=user_data.phone,
        national_id=user_data.national_id,
        birth_date=user_data.birth_date,
        pin_hash=hash_password(user_data.pin),
    )

    db.add(user)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Phone number or national ID is already registered",
        ) from None

    await db.refresh(user)
    return user


async def get_user(db: AsyncSession, user_id: int) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return user


async def get_users(
    db: AsyncSession,
    params: UserListParams,
) -> dict:
    filters = []

    if params.search:
        search_pattern = f"%{params.search}%"
        compact_search = re.sub(r"[\s\-()]", "", params.search)
        compact_pattern = f"%{compact_search}%"
        filters.append(
            or_(
                User.full_name.ilike(search_pattern),
                User.phone.ilike(compact_pattern),
                User.national_id.ilike(compact_pattern),
            )
        )

    if params.is_active is not None:
        filters.append(User.is_active == params.is_active)

    total_result = await db.execute(
        select(func.count(User.id)).where(*filters)
    )
    total = total_result.scalar_one()

    users_result = await db.execute(
        select(User)
        .where(*filters)
        .order_by(User.id)
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(users_result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }
