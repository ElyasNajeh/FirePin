from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.device_tokens.model import DeviceToken
from app.features.device_tokens.schema import DeviceTokenCreate


async def register_token(
    db: AsyncSession,
    token_data: DeviceTokenCreate,
    *,
    user_id: int | None = None,
    municipality_id: int | None = None,
) -> DeviceToken:
    result = await db.execute(
        select(DeviceToken)
        .where(DeviceToken.token == token_data.token)
        .with_for_update()
    )
    device_token = result.scalar_one_or_none()

    if device_token is None:
        device_token = DeviceToken(
            user_id=user_id,
            municipality_id=municipality_id,
            token=token_data.token,
            platform=token_data.platform.value,
        )
        db.add(device_token)
    else:
        device_token.user_id = user_id
        device_token.municipality_id = municipality_id
        device_token.platform = token_data.platform.value

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        result = await db.execute(
            select(DeviceToken)
            .where(DeviceToken.token == token_data.token)
            .with_for_update()
        )
        device_token = result.scalar_one()
        device_token.user_id = user_id
        device_token.municipality_id = municipality_id
        device_token.platform = token_data.platform.value
        await db.commit()

    await db.refresh(device_token)
    return device_token


async def remove_token(
    db: AsyncSession,
    token: str,
    *,
    user_id: int | None = None,
    municipality_id: int | None = None,
) -> dict[str, str]:
    owner_filter = (
        DeviceToken.user_id == user_id
        if user_id is not None
        else DeviceToken.municipality_id == municipality_id
    )
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == token,
            owner_filter,
        )
    )
    device_token = result.scalar_one_or_none()
    if device_token is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device token not found",
        )

    await db.delete(device_token)
    await db.commit()
    return {"message": "Device token removed successfully"}
