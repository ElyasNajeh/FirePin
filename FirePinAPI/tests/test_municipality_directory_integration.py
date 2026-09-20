import os
from decimal import Decimal
import unittest
from uuid import uuid4

from sqlalchemy import delete

from app.db.session import AsyncSessionLocal, engine
from app.features.auth.model import UserSession  # noqa: F401
from app.features.device_tokens.model import DeviceToken  # noqa: F401
from app.features.fire_reports.model import FireReport  # noqa: F401
from app.features.municipalities import service
from app.features.municipalities.model import Municipality
from app.features.municipalities.schema import MunicipalityListParams
from app.features.report_images.model import ReportImage  # noqa: F401
from app.features.users.model import User  # noqa: F401
from app.features.volunteers.model import (  # noqa: F401
    Volunteer,
    VolunteerApplication,
)


@unittest.skipUnless(
    os.getenv("FIREPIN_RUN_DB_TESTS") == "1",
    "Set FIREPIN_RUN_DB_TESTS=1 to run PostgreSQL integration tests",
)
class MunicipalityDirectoryIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        suffix = uuid4().hex
        self.search = f"directory-{suffix}"
        async with AsyncSessionLocal() as db:
            active = Municipality(
                name=f"{self.search}-active",
                email=f"active-{suffix}@example.com",
                password_hash="not-used",
                latitude=Decimal("31.532600"),
                longitude=Decimal("35.099800"),
                is_active=True,
            )
            inactive = Municipality(
                name=f"{self.search}-inactive",
                email=f"inactive-{suffix}@example.com",
                password_hash="not-used",
                latitude=Decimal("32.221100"),
                longitude=Decimal("35.254400"),
                is_active=False,
            )
            db.add_all([active, inactive])
            await db.commit()
            await db.refresh(active)
            await db.refresh(inactive)
            self.active_id = active.id
            self.inactive_id = inactive.id

    async def asyncTearDown(self) -> None:
        async with AsyncSessionLocal() as db:
            await db.execute(
                delete(Municipality).where(
                    Municipality.id.in_([self.active_id, self.inactive_id])
                )
            )
            await db.commit()
        await engine.dispose()

    async def test_active_directory_preserves_ids_and_excludes_inactive(self) -> None:
        async with AsyncSessionLocal() as db:
            result = await service.get_municipalities(
                db,
                MunicipalityListParams(
                    search=self.search,
                    is_active=True,
                    page=1,
                    limit=100,
                ),
            )

        self.assertEqual(result["total"], 1)
        self.assertEqual([item.id for item in result["items"]], [self.active_id])
        self.assertNotIn(
            self.inactive_id,
            [item.id for item in result["items"]],
        )

    async def test_active_directory_can_return_an_empty_page(self) -> None:
        async with AsyncSessionLocal() as db:
            result = await service.get_municipalities(
                db,
                MunicipalityListParams(
                    search=f"missing-{uuid4().hex}",
                    is_active=True,
                    page=1,
                    limit=100,
                ),
            )

        self.assertEqual(result["items"], [])
        self.assertEqual(result["total"], 0)


if __name__ == "__main__":
    unittest.main()
