from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.features.auth.service import get_current_user
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import get_current_municipality
from app.features.notifications.model import NotificationEvent
from app.features.notifications.schema import NotificationEventResponse
from app.features.users.model import User

router = APIRouter(tags=["Notifications"])


@router.get(
    "/notifications/me",
    response_model=list[NotificationEventResponse],
    status_code=status.HTTP_200_OK,
)
async def get_my_notifications(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[NotificationEvent]:
    result = await db.execute(
        select(NotificationEvent)
        .where(NotificationEvent.recipient_user_id == user.id)
        .order_by(NotificationEvent.id.desc())
        .limit(100)
    )
    return list(result.scalars().all())


@router.get(
    "/municipalities/auth/notifications",
    response_model=list[NotificationEventResponse],
    status_code=status.HTTP_200_OK,
)
async def get_municipality_notifications(
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> list[NotificationEvent]:
    result = await db.execute(
        select(NotificationEvent)
        .where(NotificationEvent.recipient_municipality_id == municipality.id)
        .order_by(NotificationEvent.id.desc())
        .limit(100)
    )
    return list(result.scalars().all())
