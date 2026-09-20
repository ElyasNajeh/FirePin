import json
import os
import socket
import tempfile
import unittest
from datetime import date, timedelta
from decimal import Decimal
from io import BytesIO
from pathlib import Path
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from fastapi import HTTPException, UploadFile
from fastapi.security import HTTPAuthorizationCredentials
from PIL import Image
from pydantic import ValidationError
from sqlalchemy import delete, select
from urllib.error import HTTPError, URLError

from app.core.config import settings
from app.core.security import hash_password
from app.db.session import AsyncSessionLocal, engine
from app.features.auth.model import UserSession  # noqa: F401
from app.features.auth.service import create_user_token
from app.features.device_tokens.model import DeviceToken  # noqa: F401
from app.features.fire_reports import router as report_router
from app.features.fire_reports import service as report_service
from app.features.fire_reports.model import FireReport
from app.features.fire_reports.schema import FireReportCreate, FireReportListParams
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import create_municipality_token
from app.features.report_images import router as image_router
from app.features.report_images.model import ReportImage
from app.features.routing.schema import RouteOrigin
from app.features.routing.service import RoutingProviderResponse, ValhallaRoutingService
from app.features.users import service as user_service
from app.features.users.model import User
from app.features.users.schema import UserRegister
from app.features.volunteers.model import Volunteer, VolunteerApplication


def png_bytes() -> bytes:
    output = BytesIO()
    Image.new("RGB", (2, 2), color=(255, 0, 0)).save(output, format="PNG")
    return output.getvalue()


def uploads(count: int) -> list[UploadFile]:
    data = png_bytes()
    return [
        UploadFile(file=BytesIO(data), filename=f"fire-{index}.png")
        for index in range(count)
    ]


class ValhallaRoutingServiceTests(unittest.IsolatedAsyncioTestCase):
    def test_invalid_origin_coordinates_are_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            RouteOrigin(latitude=Decimal("91"), longitude=Decimal("35"))

    async def test_driving_payload_and_owned_response_mapping(self) -> None:
        captured = {}

        def provider(url: str, payload: bytes, timeout: float):
            captured.update(
                url=url,
                payload=json.loads(payload),
                timeout=timeout,
            )
            return RoutingProviderResponse(
                200,
                json.dumps(
                    {
                        "trip": {
                            "summary": {"length": 3.4, "time": 421.2},
                            "legs": [{"shape": "_izlhA~rlgdF_{geC~ywl@"}],
                        }
                    }
                ).encode(),
            )

        service = ValhallaRoutingService(
            base_url="http://routing.test/",
            timeout_seconds=2.5,
            provider_request=provider,
        )
        result = await service.route(
            Decimal("38.500000"),
            Decimal("-120.200000"),
            Decimal("40.700000"),
            Decimal("-120.950000"),
        )

        self.assertEqual(captured["url"], "http://routing.test/route")
        self.assertEqual(captured["payload"]["costing"], "auto")
        self.assertEqual(captured["payload"]["units"], "kilometers")
        self.assertEqual(captured["payload"]["locations"][1]["lat"], 40.7)
        self.assertEqual(result["distance_km"], 3.4)
        self.assertEqual(result["duration_seconds"], 421)
        self.assertEqual(result["geometry"][0]["latitude"], 38.5)
        self.assertGreaterEqual(len(result["geometry"]), 2)

    async def test_provider_unavailable_timeout_and_no_route(self) -> None:
        failures = [
            (lambda *_: (_ for _ in ()).throw(URLError("offline")), 503),
            (lambda *_: (_ for _ in ()).throw(socket.timeout()), 504),
            (
                lambda *_: (_ for _ in ()).throw(
                    HTTPError("url", 400, "no route", {}, None)
                ),
                422,
            ),
            (lambda *_: RoutingProviderResponse(200, b'{"trip":{}}'), 422),
        ]
        for provider, expected_status in failures:
            with self.subTest(status=expected_status):
                service = ValhallaRoutingService(provider_request=provider)
                with self.assertRaises(HTTPException) as failure:
                    await service.route(
                        Decimal("31.78"),
                        Decimal("35.24"),
                        Decimal("31.79"),
                        Decimal("35.25"),
                    )
                self.assertEqual(failure.exception.status_code, expected_status)


@unittest.skipUnless(
    os.getenv("FIREPIN_RUN_DB_TESTS") == "1",
    "Set FIREPIN_RUN_DB_TESTS=1 to run PostgreSQL integration tests",
)
class FireReportIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temp_uploads = tempfile.TemporaryDirectory()
        self.original_upload_root = settings.UPLOAD_ROOT
        settings.UPLOAD_ROOT = Path(self.temp_uploads.name)
        suffix = uuid4().hex
        async with AsyncSessionLocal() as db:
            self.user = await user_service.register_user(
                db,
                UserRegister(
                    full_name="Fire Reporter",
                    phone=f"059{str(uuid4().int)[:7]}",
                    national_id=str(uuid4().int)[:9],
                    birth_date=date(1995, 1, 2),
                    pin="2468",
                ),
            )
            self.other_user = await user_service.register_user(
                db,
                UserRegister(
                    full_name="Other Reporter",
                    phone=f"056{str(uuid4().int)[:7]}",
                    national_id=str(uuid4().int)[:9],
                    birth_date=date(1996, 2, 3),
                    pin="1357",
                ),
            )
            self.near = Municipality(
                name=f"Near {suffix}",
                email=f"near-{suffix}@example.com",
                password_hash=hash_password("password"),
                latitude=Decimal("31.780000"),
                longitude=Decimal("35.240000"),
                is_active=True,
            )
            self.far = Municipality(
                name=f"Far {suffix}",
                email=f"far-{suffix}@example.com",
                password_hash=hash_password("password"),
                latitude=Decimal("32.000000"),
                longitude=Decimal("35.500000"),
                is_active=True,
            )
            self.inactive = Municipality(
                name=f"Inactive {suffix}",
                email=f"inactive-{suffix}@example.com",
                password_hash=hash_password("password"),
                latitude=Decimal("31.781000"),
                longitude=Decimal("35.241000"),
                is_active=False,
            )
            db.add_all([self.near, self.far, self.inactive])
            await db.commit()
            for municipality in (self.near, self.far, self.inactive):
                await db.refresh(municipality)
            self.volunteer = Volunteer(
                user_id=self.other_user.id,
                municipality_id=self.near.id,
            )
            db.add(self.volunteer)
            await db.commit()
            await db.refresh(self.volunteer)

        self.user_id = self.user.id
        self.other_user_id = self.other_user.id
        self.municipality_ids = [self.near.id, self.far.id, self.inactive.id]

    async def asyncTearDown(self) -> None:
        async with AsyncSessionLocal() as db:
            await db.execute(
                delete(FireReport).where(
                    FireReport.reporter_id.in_([self.user_id, self.other_user_id])
                )
            )
            await db.execute(
                delete(Volunteer).where(
                    Volunteer.user_id.in_([self.user_id, self.other_user_id])
                )
            )
            await db.execute(
                delete(VolunteerApplication).where(
                    VolunteerApplication.user_id.in_(
                        [self.user_id, self.other_user_id]
                    )
                )
            )
            await db.execute(
                delete(User).where(User.id.in_([self.user_id, self.other_user_id]))
            )
            await db.execute(
                delete(Municipality).where(
                    Municipality.id.in_(self.municipality_ids)
                )
            )
            await db.commit()
        settings.UPLOAD_ROOT = self.original_upload_root
        self.temp_uploads.cleanup()
        await engine.dispose()

    async def create(
        self,
        user: User,
        image_count: int = 0,
        pin: str | None = "2468",
        latitude: str = "31.782000",
        longitude: str = "35.242000",
    ) -> FireReport:
        report_uploads = uploads(image_count)
        try:
            with patch.object(
                report_service.notification_service,
                "notify_report_created",
                new=AsyncMock(),
            ):
                async with AsyncSessionLocal() as db:
                    return await report_service.create_report(
                        db,
                        user,
                        FireReportCreate(
                            latitude=Decimal(latitude),
                            longitude=Decimal(longitude),
                        ),
                        report_uploads,
                        pin,
                    )
        finally:
            for upload in report_uploads:
                await upload.close()

    async def test_pin_image_counts_and_nearest_active_municipality(self) -> None:
        no_image = await self.create(self.user)
        self.assertEqual(no_image.municipality_id, self.near.id)
        self.assertEqual(len(no_image.images), 0)

        for pin in (None, "9999"):
            with self.subTest(pin=pin):
                with self.assertRaises(HTTPException) as rejected:
                    await self.create(self.user, pin=pin)
                self.assertEqual(rejected.exception.status_code, 422)

        one_image = await self.create(self.user, image_count=1, pin=None)
        five_images = await self.create(self.user, image_count=5, pin=None)
        self.assertEqual(len(one_image.images), 1)
        self.assertEqual(len(five_images.images), 5)

        with self.assertRaises(HTTPException) as too_many:
            await self.create(self.user, image_count=6, pin=None)
        self.assertEqual(too_many.exception.status_code, 422)

    async def test_own_reports_and_protected_image_access(self) -> None:
        mine = await self.create(self.user, image_count=1, pin=None)
        await self.create(self.other_user, pin="1357")
        async with AsyncSessionLocal() as db:
            page = await report_service.get_user_reports(
                db,
                self.user,
                FireReportListParams(page=1, limit=100),
            )
            self.assertEqual(page["total"], 1)
            self.assertEqual(page["items"][0].id, mine.id)

            token = create_user_token(
                self.user.id,
                "access",
                timedelta(minutes=5),
            )
            image = await image_router.get_authorized_image(
                db,
                HTTPAuthorizationCredentials(scheme="Bearer", credentials=token),
                mine.id,
                mine.images[0].id,
            )
            self.assertEqual(image.report_id, mine.id)

            other_token = create_municipality_token(
                self.far.id,
                "access",
                timedelta(minutes=5),
            )
            with self.assertRaises(HTTPException) as hidden:
                await image_router.get_authorized_image(
                    db,
                    HTTPAuthorizationCredentials(
                        scheme="Bearer",
                        credentials=other_token,
                    ),
                    mine.id,
                    mine.images[0].id,
                )
            self.assertEqual(hidden.exception.status_code, 404)

    async def test_route_uses_stored_destination_and_failure_is_read_only(self) -> None:
        report = await self.create(
            self.user,
            latitude="31.799111",
            longitude="35.266222",
        )
        expected = {
            "geometry": [
                {"latitude": 31.7, "longitude": 35.2},
                {"latitude": 31.799111, "longitude": 35.266222},
            ],
            "distance_km": 2.1,
            "duration_seconds": 240,
        }
        with patch.object(
            report_router.routing_service,
            "route",
            new=AsyncMock(return_value=expected),
        ) as route:
            async with AsyncSessionLocal() as db:
                result = await report_router.get_volunteer_report_route(
                    RouteOrigin(latitude=Decimal("31.7"), longitude=Decimal("35.2")),
                    report.id,
                    self.volunteer,
                    db,
                )
        self.assertEqual(result, expected)
        args = route.await_args.args
        self.assertEqual(args[2], Decimal("31.799111"))
        self.assertEqual(args[3], Decimal("35.266222"))

        with patch.object(
            report_router.routing_service,
            "route",
            new=AsyncMock(
                side_effect=HTTPException(status_code=503, detail="unavailable")
            ),
        ):
            async with AsyncSessionLocal() as db:
                with self.assertRaises(HTTPException):
                    await report_router.get_volunteer_report_route(
                        RouteOrigin(
                            latitude=Decimal("31.7"),
                            longitude=Decimal("35.2"),
                        ),
                        report.id,
                        self.volunteer,
                        db,
                    )
                persisted = await db.scalar(
                    select(FireReport).where(FireReport.id == report.id)
                )
                self.assertIsNotNone(persisted)
                self.assertEqual(persisted.status, "pending")


if __name__ == "__main__":
    unittest.main()
