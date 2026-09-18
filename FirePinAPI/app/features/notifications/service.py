import asyncio
from functools import lru_cache
import logging

import firebase_admin
from firebase_admin import credentials, exceptions, messaging
from sqlalchemy import delete, select

from app.core.config import settings
from app.db.session import AsyncSessionLocal
from app.features.device_tokens.model import DeviceToken
from app.features.fire_reports.model import FireReport
from app.features.volunteers.model import Volunteer

logger = logging.getLogger(__name__)

MAX_MULTICAST_TOKENS = 500


@lru_cache(maxsize=1)
def get_firebase_app() -> firebase_admin.App | None:
    credentials_path = settings.FIREBASE_CREDENTIALS_PATH
    if credentials_path is None:
        logger.warning(
            "FCM delivery is disabled because FIREBASE_CREDENTIALS_PATH is not set"
        )
        return None

    try:
        credential = credentials.Certificate(str(credentials_path))
        return firebase_admin.initialize_app(credential)
    except (OSError, ValueError) as error:
        logger.error(
            "FCM initialization failed (%s); notification delivery is disabled",
            type(error).__name__,
        )
        return None


def token_batches(tokens: list[str]) -> list[list[str]]:
    unique_tokens = list(dict.fromkeys(tokens))
    return [
        unique_tokens[index : index + MAX_MULTICAST_TOKENS]
        for index in range(0, len(unique_tokens), MAX_MULTICAST_TOKENS)
    ]


async def remove_unregistered_tokens(tokens: list[str]) -> None:
    if not tokens:
        return

    try:
        async with AsyncSessionLocal() as db:
            await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(tokens)))
            await db.commit()
    except Exception as error:
        logger.error(
            "Unable to remove unregistered FCM tokens (%s)",
            type(error).__name__,
        )


async def send_notification(
    tokens: list[str],
    *,
    title: str,
    body: str,
    data: dict[str, str],
) -> None:
    batches = token_batches(tokens)
    if not batches:
        return

    app = get_firebase_app()
    if app is None:
        return

    for batch in batches:
        message = messaging.MulticastMessage(
            tokens=batch,
            notification=messaging.Notification(title=title, body=body),
            data=data,
        )
        try:
            response = await asyncio.to_thread(
                messaging.send_each_for_multicast,
                message,
                False,
                app,
            )
        except (exceptions.FirebaseError, ValueError) as error:
            logger.error(
                "FCM batch delivery failed for %d devices (%s)",
                len(batch),
                type(error).__name__,
            )
            continue

        unregistered_tokens = [
            token
            for token, send_response in zip(batch, response.responses, strict=True)
            if not send_response.success
            and isinstance(send_response.exception, messaging.UnregisteredError)
        ]
        await remove_unregistered_tokens(unregistered_tokens)

        if response.failure_count:
            logger.warning(
                "FCM batch completed with %d successes and %d failures",
                response.success_count,
                response.failure_count,
            )


async def notify_report_created(report: FireReport) -> None:
    try:
        async with AsyncSessionLocal() as db:
            tokens = list(
                (
                    await db.execute(
                        select(DeviceToken.token)
                        .join(Volunteer, Volunteer.user_id == DeviceToken.user_id)
                        .where(
                            Volunteer.municipality_id == report.municipality_id,
                            Volunteer.user_id != report.reporter_id,
                        )
                    )
                ).scalars()
            )

        await send_notification(
            tokens,
            title="بلاغ حريق جديد",
            body="تم تسجيل بلاغ حريق جديد بالقرب منك",
            data={
                "event_type": "fire_report_created",
                "report_id": str(report.id),
            },
        )
    except Exception as error:
        logger.error(
            "New-report notification processing failed for report %s (%s)",
            report.id,
            type(error).__name__,
        )


async def notify_report_claimed(report: FireReport) -> None:
    volunteer = report.assigned_volunteer
    if volunteer is None:
        return

    volunteer_user = volunteer.user
    try:
        async with AsyncSessionLocal() as db:
            reporter_tokens = list(
                (
                    await db.execute(
                        select(DeviceToken.token).where(
                            DeviceToken.user_id == report.reporter_id
                        )
                    )
                ).scalars()
            )
            other_volunteer_tokens = list(
                (
                    await db.execute(
                        select(DeviceToken.token)
                        .join(Volunteer, Volunteer.user_id == DeviceToken.user_id)
                        .where(
                            Volunteer.municipality_id == report.municipality_id,
                            Volunteer.id != volunteer.id,
                            Volunteer.user_id != report.reporter_id,
                        )
                    )
                ).scalars()
            )
            municipality_tokens = list(
                (
                    await db.execute(
                        select(DeviceToken.token).where(
                            DeviceToken.municipality_id == report.municipality_id
                        )
                    )
                ).scalars()
            )

        base_data = {
            "event_type": "fire_report_claimed",
            "report_id": str(report.id),
            "volunteer_full_name": volunteer_user.full_name,
        }
        await send_notification(
            reporter_tokens,
            title="تم استلام بلاغك",
            body=f"تم استلام بلاغك بواسطة {volunteer_user.full_name}",
            data={
                **base_data,
                "volunteer_phone": volunteer_user.phone,
            },
        )
        await send_notification(
            other_volunteer_tokens,
            title="تم استلام البلاغ",
            body=f"تم استلام البلاغ بواسطة {volunteer_user.full_name}",
            data=base_data,
        )
        await send_notification(
            municipality_tokens,
            title="تم استلام البلاغ",
            body=f"تم استلام البلاغ بواسطة {volunteer_user.full_name}",
            data=base_data,
        )
    except Exception as error:
        logger.error(
            "Claim notification processing failed for report %s (%s)",
            report.id,
            type(error).__name__,
        )


async def notify_report_resolved(report: FireReport) -> None:
    try:
        async with AsyncSessionLocal() as db:
            reporter_tokens = list(
                (
                    await db.execute(
                        select(DeviceToken.token).where(
                            DeviceToken.user_id == report.reporter_id
                        )
                    )
                ).scalars()
            )
            municipality_tokens = list(
                (
                    await db.execute(
                        select(DeviceToken.token).where(
                            DeviceToken.municipality_id == report.municipality_id
                        )
                    )
                ).scalars()
            )

        data = {
            "event_type": "fire_report_resolved",
            "report_id": str(report.id),
        }
        await send_notification(
            reporter_tokens,
            title="تم إنهاء البلاغ",
            body="تم إنهاء التعامل مع البلاغ",
            data=data,
        )
        await send_notification(
            municipality_tokens,
            title="تم إنهاء البلاغ",
            body="تم إنهاء التعامل مع البلاغ",
            data=data,
        )
    except Exception as error:
        logger.error(
            "Resolve notification processing failed for report %s (%s)",
            report.id,
            type(error).__name__,
        )
