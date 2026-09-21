import asyncio
from datetime import date
from decimal import Decimal
import os
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from fastapi import HTTPException
from firebase_admin import messaging
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, select

from app.core.security import access_token_lifetime
from app.db.session import AsyncSessionLocal, engine
from app.features.auth.service import create_user_token
from app.features.auth.model import UserSession  # noqa: F401
from app.features.device_tokens import service as device_token_service
from app.features.device_tokens.model import DeviceToken
from app.features.device_tokens.schema import DevicePlatform, DeviceTokenCreate
from app.features.fire_reports import service as fire_report_service
from app.features.fire_reports.model import FireReport, FireReportStatus
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import create_municipality_token
from app.features.notifications.model import NotificationEvent
from app.features.notifications import service as notification_service
from app.features.users.model import User
from app.features.volunteers.model import Volunteer
from app.main import app


@unittest.skipUnless(
    os.getenv("FIREPIN_RUN_DB_TESTS") == "1",
    "Set FIREPIN_RUN_DB_TESTS=1 to run PostgreSQL integration tests",
)
class NotificationIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        suffix = uuid4().hex[:10]
        self.token_prefix = f"notification-test-{suffix}"

        async with AsyncSessionLocal() as db:
            municipality = Municipality(
                name=f"Notification municipality {suffix}",
                email=f"notification-{suffix}@example.com",
                password_hash="not-used",
                latitude=Decimal("31.780000"),
                longitude=Decimal("35.240000"),
            )
            other_municipality = Municipality(
                name=f"Other municipality {suffix}",
                email=f"other-{suffix}@example.com",
                password_hash="not-used",
                latitude=Decimal("31.790000"),
                longitude=Decimal("35.250000"),
            )
            db.add_all([municipality, other_municipality])
            await db.flush()

            users = [
                User(
                    full_name=f"Test user {index}",
                    phone=f"059{suffix[:7]}{index}",
                    national_id=f"{suffix[:8]}{index}",
                    birth_date=date(1990, 1, index + 1),
                    pin_hash="not-used",
                )
                for index in range(4)
            ]
            db.add_all(users)
            await db.flush()

            volunteers = [
                Volunteer(user_id=users[1].id, municipality_id=municipality.id),
                Volunteer(user_id=users[2].id, municipality_id=municipality.id),
                Volunteer(
                    user_id=users[3].id,
                    municipality_id=other_municipality.id,
                ),
            ]
            db.add_all(volunteers)
            await db.flush()

            report = FireReport(
                reporter_id=users[0].id,
                municipality_id=municipality.id,
                latitude=Decimal("31.781000"),
                longitude=Decimal("35.241000"),
                status=FireReportStatus.PENDING.value,
            )
            db.add(report)
            await db.flush()

            tokens = [
                DeviceToken(
                    user_id=users[index].id,
                    token=f"{self.token_prefix}-user-{index}",
                    platform=DevicePlatform.ANDROID.value,
                )
                for index in range(4)
            ]
            tokens.extend(
                [
                    DeviceToken(
                        municipality_id=municipality.id,
                        token=f"{self.token_prefix}-municipality",
                        platform=DevicePlatform.ANDROID.value,
                    ),
                    DeviceToken(
                        municipality_id=other_municipality.id,
                        token=f"{self.token_prefix}-other-municipality",
                        platform=DevicePlatform.ANDROID.value,
                    ),
                ]
            )
            db.add_all(tokens)
            await db.commit()

            self.municipality_id = municipality.id
            self.other_municipality_id = other_municipality.id
            self.user_ids = [user.id for user in users]
            self.volunteer_ids = [volunteer.id for volunteer in volunteers]
            self.report_id = report.id

    async def asyncTearDown(self) -> None:
        async with AsyncSessionLocal() as db:
            await db.execute(
                delete(DeviceToken).where(
                    DeviceToken.token.like(f"{self.token_prefix}%")
                )
            )
            await db.execute(
                delete(FireReport).where(FireReport.reporter_id.in_(self.user_ids))
            )
            await db.execute(
                delete(Volunteer).where(Volunteer.user_id.in_(self.user_ids))
            )
            await db.execute(delete(User).where(User.id.in_(self.user_ids)))
            await db.execute(
                delete(Municipality).where(
                    Municipality.id.in_(
                        [self.municipality_id, self.other_municipality_id]
                    )
                )
            )
            await db.commit()
        await engine.dispose()

    async def test_notification_recipients_and_payloads(self) -> None:
        report = SimpleNamespace(
            id=self.report_id,
            reporter_id=self.user_ids[0],
            municipality_id=self.municipality_id,
        )

        with patch.object(
            notification_service,
            "send_notification",
            new_callable=AsyncMock,
        ) as send:
            await notification_service.notify_report_created(report)
            created = send.await_args
            self.assertEqual(
                set(created.args[0]),
                {
                    f"{self.token_prefix}-user-1",
                    f"{self.token_prefix}-user-2",
                    f"{self.token_prefix}-municipality",
                },
            )
            self.assertEqual(created.kwargs["data"]["type"], "fire_report_created")
            self.assertTrue(created.kwargs["emergency"])

        claimed_report = SimpleNamespace(
            **report.__dict__,
            assigned_volunteer=SimpleNamespace(
                id=self.volunteer_ids[0],
                user=SimpleNamespace(
                    full_name="Safe Volunteer",
                    phone="0590000000",
                ),
            ),
        )
        with patch.object(
            notification_service,
            "send_notification",
            new_callable=AsyncMock,
        ) as send:
            await notification_service.notify_report_claimed(claimed_report)
            claimed = send.await_args
            self.assertEqual(
                set(claimed.args[0]),
                {
                    f"{self.token_prefix}-user-0",
                    f"{self.token_prefix}-user-1",
                    f"{self.token_prefix}-user-2",
                    f"{self.token_prefix}-municipality",
                },
            )
            self.assertEqual(claimed.kwargs["data"]["type"], "fire_report_claimed")
            self.assertEqual(
                set(claimed.kwargs["data"]),
                {"type", "report_id", "volunteer_name", "volunteer_phone"},
            )

        with patch.object(
            notification_service,
            "send_notification",
            new_callable=AsyncMock,
        ) as send:
            await notification_service.notify_report_resolved(report)
            resolved = send.await_args
            self.assertEqual(
                set(resolved.args[0]),
                {
                    f"{self.token_prefix}-user-0",
                    f"{self.token_prefix}-municipality",
                },
            )
            self.assertEqual(
                resolved.kwargs["data"]["type"],
                "fire_report_resolved",
            )

    async def test_persisted_history_is_recipient_scoped_and_token_independent(self) -> None:
        async with AsyncSessionLocal() as db:
            await db.execute(
                delete(DeviceToken).where(DeviceToken.user_id == self.user_ids[2])
            )
            await db.commit()

        report = SimpleNamespace(
            id=self.report_id,
            reporter_id=self.user_ids[0],
            municipality_id=self.municipality_id,
            assigned_volunteer=SimpleNamespace(
                id=self.volunteer_ids[0],
                user=SimpleNamespace(full_name="Safe Volunteer", phone="0590000000"),
            ),
        )
        with patch.object(
            notification_service, "send_notification", new_callable=AsyncMock
        ):
            await notification_service.notify_report_created(report)
            await notification_service.notify_report_claimed(report)
            await notification_service.notify_report_resolved(report)

        async with AsyncSessionLocal() as db:
            events = list(
                (await db.execute(
                    select(NotificationEvent).where(
                        NotificationEvent.fire_report_id == self.report_id
                    )
                )).scalars()
            )
        by_user = {
            user_id: {item.event_type for item in events if item.recipient_user_id == user_id}
            for user_id in self.user_ids
        }
        self.assertEqual(
            by_user[self.user_ids[0]],
            {"report_created", "report_claimed", "report_resolved"},
        )
        self.assertEqual(
            by_user[self.user_ids[1]], {"new_report", "report_claimed"}
        )
        self.assertEqual(
            by_user[self.user_ids[2]], {"new_report", "report_claimed"}
        )
        self.assertEqual(by_user[self.user_ids[3]], set())
        self.assertEqual(
            {item.event_type for item in events if item.recipient_municipality_id == self.municipality_id},
            {"report_created", "report_claimed", "report_resolved"},
        )
        self.assertFalse(
            any(item.recipient_municipality_id == self.other_municipality_id for item in events)
        )

        user_token = create_user_token(
            self.user_ids[2], "access", access_token_lifetime()
        )
        municipality_token = create_municipality_token(
            self.municipality_id, "access", access_token_lifetime()
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            user_history = await client.get(
                "/notifications/me",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            self.assertEqual(user_history.status_code, 200)
            self.assertEqual(
                {item["event_type"] for item in user_history.json()},
                {"new_report", "report_claimed"},
            )
            self.assertTrue(all(item["fire_report_id"] == self.report_id for item in user_history.json()))
            municipality_history = await client.get(
                "/municipalities/auth/notifications",
                headers={"Authorization": f"Bearer {municipality_token}"},
            )
            self.assertEqual(municipality_history.status_code, 200)
            self.assertEqual(len(municipality_history.json()), 3)
            wrong_type = await client.get(
                "/municipalities/auth/notifications",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            self.assertEqual(wrong_type.status_code, 401)

    async def test_all_active_volunteer_devices_and_municipality_receive_alerts(self) -> None:
        async with AsyncSessionLocal() as db:
            inactive = await db.get(User, self.user_ids[2])
            inactive.is_active = False
            db.add_all(
                [
                    DeviceToken(
                        user_id=self.user_ids[1],
                        token=f"{self.token_prefix}-user-1-extra",
                        platform=DevicePlatform.ANDROID.value,
                    ),
                    DeviceToken(
                        municipality_id=self.municipality_id,
                        token=f"{self.token_prefix}-municipality-extra",
                        platform=DevicePlatform.ANDROID.value,
                    ),
                ]
            )
            await db.commit()

        report = SimpleNamespace(
            id=self.report_id,
            reporter_id=self.user_ids[0],
            municipality_id=self.municipality_id,
            assigned_volunteer=SimpleNamespace(
                id=self.volunteer_ids[0],
                user=SimpleNamespace(full_name="Safe Volunteer", phone="0590000000"),
            ),
        )
        expected = {
            f"{self.token_prefix}-user-1",
            f"{self.token_prefix}-user-1-extra",
            f"{self.token_prefix}-municipality",
            f"{self.token_prefix}-municipality-extra",
        }
        with patch.object(
            notification_service, "send_notification", new_callable=AsyncMock
        ) as send:
            await notification_service.notify_report_created(report)
            self.assertEqual(set(send.await_args.args[0]), expected)
            await notification_service.notify_report_claimed(report)
            self.assertEqual(
                set(send.await_args.args[0]),
                expected | {f"{self.token_prefix}-user-0"},
            )

    async def test_device_token_upsert_reassignment_and_owned_removal(self) -> None:
        token = f"{self.token_prefix}-lifecycle"
        token_data = DeviceTokenCreate(token=token, platform="ANDROID")

        async with AsyncSessionLocal() as db:
            registered = await device_token_service.register_token(
                db,
                token_data,
                user_id=self.user_ids[0],
            )
            self.assertEqual(registered.user_id, self.user_ids[0])
            self.assertIsNone(registered.municipality_id)

            reassigned = await device_token_service.register_token(
                db,
                token_data,
                municipality_id=self.municipality_id,
            )
            self.assertIsNone(reassigned.user_id)
            self.assertEqual(reassigned.municipality_id, self.municipality_id)

            with self.assertRaises(HTTPException) as wrong_owner:
                await device_token_service.remove_token(
                    db,
                    token,
                    user_id=self.user_ids[0],
                )
            self.assertEqual(wrong_owner.exception.status_code, 404)

            await device_token_service.remove_token(
                db,
                token,
                municipality_id=self.municipality_id,
            )
            self.assertIsNone(
                (
                    await db.execute(
                        select(DeviceToken).where(DeviceToken.token == token)
                    )
                ).scalar_one_or_none()
            )

    async def test_unregistered_token_cleanup_is_selective(self) -> None:
        invalid_token = f"{self.token_prefix}-user-1"
        retained_token = f"{self.token_prefix}-user-2"
        sent_messages = []

        def fake_send(message, dry_run, app):
            sent_messages.append(message)
            return messaging.BatchResponse(
                [
                    messaging.SendResponse(
                        None,
                        messaging.UnregisteredError("unregistered"),
                    ),
                    messaging.SendResponse(None, RuntimeError("transient")),
                ]
            )

        with (
            patch.object(
                notification_service,
                "get_firebase_app",
                return_value=object(),
            ),
            patch.object(
                notification_service.messaging,
                "send_each_for_multicast",
                side_effect=fake_send,
            ),
        ):
            await notification_service.send_notification(
                [invalid_token, retained_token],
                title="Emergency",
                body="Body",
                data={"type": "fire_report_created", "report_id": "1"},
                emergency=True,
            )

        async with AsyncSessionLocal() as db:
            remaining = set(
                (
                    await db.execute(
                        select(DeviceToken.token).where(
                            DeviceToken.token.in_([invalid_token, retained_token])
                        )
                    )
                ).scalars()
            )
        self.assertEqual(remaining, {retained_token})
        android = sent_messages[0].android
        self.assertEqual(android.priority, "high")
        self.assertEqual(
            android.notification.channel_id,
            notification_service.FIRE_EMERGENCY_CHANNEL_ID,
        )
        self.assertEqual(
            android.notification.sound,
            notification_service.FIRE_EMERGENCY_SOUND,
        )
        self.assertTrue(android.notification.default_sound)

    async def test_only_one_concurrent_claim_commits_and_notifies(self) -> None:
        async with AsyncSessionLocal() as first_db, AsyncSessionLocal() as second_db:
            first_volunteer = await first_db.get(Volunteer, self.volunteer_ids[0])
            second_volunteer = await second_db.get(Volunteer, self.volunteer_ids[1])
            notify = AsyncMock()
            with patch.object(
                notification_service,
                "notify_report_claimed",
                notify,
            ):
                results = await asyncio.gather(
                    fire_report_service.claim_report(
                        first_db,
                        first_volunteer,
                        self.report_id,
                    ),
                    fire_report_service.claim_report(
                        second_db,
                        second_volunteer,
                        self.report_id,
                    ),
                    return_exceptions=True,
                )

        successes = [result for result in results if isinstance(result, FireReport)]
        conflicts = [result for result in results if isinstance(result, HTTPException)]
        self.assertEqual(len(successes), 1)
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0].status_code, 409)
        self.assertEqual(notify.await_count, 1)

        async with AsyncSessionLocal() as db:
            report = await db.get(FireReport, self.report_id)
            self.assertEqual(report.status, FireReportStatus.ASSIGNED.value)
            self.assertIn(report.assigned_volunteer_id, self.volunteer_ids[:2])

    async def test_notification_failure_does_not_undo_claim(self) -> None:
        async with AsyncSessionLocal() as db:
            volunteer = await db.get(Volunteer, self.volunteer_ids[0])
            with patch.object(
                notification_service,
                "send_notification",
                AsyncMock(side_effect=RuntimeError("mock FCM failure")),
            ):
                report = await fire_report_service.claim_report(
                    db,
                    volunteer,
                    self.report_id,
                )

        self.assertEqual(report.status, FireReportStatus.ASSIGNED.value)
        async with AsyncSessionLocal() as db:
            persisted = await db.get(FireReport, self.report_id)
            self.assertEqual(persisted.status, FireReportStatus.ASSIGNED.value)
            self.assertEqual(persisted.assigned_volunteer_id, self.volunteer_ids[0])


if __name__ == "__main__":
    unittest.main()
