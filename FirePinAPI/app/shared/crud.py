from collections.abc import Mapping
from typing import Any, TypeVar

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

ModelType = TypeVar("ModelType")


async def get_by_id(
    db: AsyncSession,
    model: type[ModelType],
    record_id: Any,
) -> ModelType | None:
    return await db.get(model, record_id)


async def get_all(
    db: AsyncSession,
    model: type[ModelType],
) -> list[ModelType]:
    result = await db.execute(select(model))
    return list(result.scalars().all())


async def create(db: AsyncSession, db_obj: ModelType) -> ModelType:
    db.add(db_obj)
    await db.commit()
    await db.refresh(db_obj)
    return db_obj


async def update(
    db: AsyncSession,
    db_obj: ModelType,
    values: Mapping[str, Any],
) -> ModelType:
    for field, value in values.items():
        setattr(db_obj, field, value)

    await db.commit()
    await db.refresh(db_obj)
    return db_obj


async def delete(db: AsyncSession, db_obj: ModelType) -> ModelType:
    await db.delete(db_obj)
    await db.commit()
    return db_obj
