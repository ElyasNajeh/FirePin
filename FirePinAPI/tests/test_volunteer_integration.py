import os
from datetime import date
from decimal import Decimal
import unittest
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy import delete

from app.core.security import hash_password
from app.db.session import AsyncSessionLocal, engine
from app.features.auth.model import UserSession  # noqa: F401
from app.features.auth import service as auth_service
from app.features.device_tokens.model import DeviceToken  # noqa: F401
from app.features.fire_reports.model import FireReport  # noqa: F401
from app.features.municipalities.model import Municipality
from app.features.report_images.model import ReportImage  # noqa: F401
from app.features.users import service as user_service
from app.features.users.model import User
from app.features.users.schema import UserRegister
from app.features.volunteers import service
from app.features.volunteers.model import (
    Volunteer,
    VolunteerApplication,
    VolunteerApplicationStatus,
)
from app.features.volunteers.schema import (
    MunicipalityApplicationListParams,
    MunicipalityVolunteerListParams,
    UserApplicationListParams,
    VolunteerApplicationCreate,
)


@unittest.skipUnless(
    os.getenv("FIREPIN_RUN_DB_TESTS") == "1",
    "Set FIREPIN_RUN_DB_TESTS=1 to run PostgreSQL integration tests",
)
class VolunteerIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        suffix = uuid4().hex
        async with AsyncSessionLocal() as db:
            self.user = await user_service.register_user(
                db,
                UserRegister(
                    full_name="Volunteer Applicant One",
                    phone=f"059{str(uuid4().int)[:7]}",
                    national_id=str(uuid4().int)[:9],
                    birth_date=date(1997, 2, 3),
                    pin="2468",
                ),
            )
            self.second_user = await user_service.register_user(
                db,
                UserRegister(
                    full_name="Volunteer Applicant Two",
                    phone=f"056{str(uuid4().int)[:7]}",
                    national_id=str(uuid4().int)[:9],
                    birth_date=date(1998, 4, 5),
                    pin="1357",
                ),
            )
            self.municipality = Municipality(
                name=f"Volunteer municipality {suffix}",
                email=f"volunteer-{suffix}@example.com",
                password_hash=hash_password("not-used"),
                latitude=Decimal("31.780000"),
                longitude=Decimal("35.240000"),
                is_active=True,
            )
            self.other_municipality = Municipality(
                name=f"Other municipality {suffix}",
                email=f"other-{suffix}@example.com",
                password_hash=hash_password("not-used"),
                latitude=Decimal("31.900000"),
                longitude=Decimal("35.300000"),
                is_active=True,
            )
            db.add_all([self.municipality, self.other_municipality])
            await db.commit()
            await db.refresh(self.municipality)
            await db.refresh(self.other_municipality)

        self.user_id = self.user.id
        self.second_user_id = self.second_user.id
        self.municipality_id = self.municipality.id
        self.other_municipality_id = self.other_municipality.id

    async def asyncTearDown(self) -> None:
        async with AsyncSessionLocal() as db:
            await db.execute(
                delete(Volunteer).where(
                    Volunteer.user_id.in_([self.user_id, self.second_user_id])
                )
            )
            await db.execute(
                delete(VolunteerApplication).where(
                    VolunteerApplication.user_id.in_(
                        [self.user_id, self.second_user_id]
                    )
                )
            )
            await db.execute(
                delete(User).where(
                    User.id.in_([self.user_id, self.second_user_id])
                )
            )
            await db.execute(
                delete(Municipality).where(
                    Municipality.id.in_(
                        [self.municipality_id, self.other_municipality_id]
                    )
                )
            )
            await db.commit()
        await engine.dispose()

    async def test_pending_duplicate_rejection_and_reapplication(self) -> None:
        async with AsyncSessionLocal() as db:
            application = await service.submit_application(
                db,
                self.user,
                VolunteerApplicationCreate(
                    municipality_id=self.municipality_id
                ),
            )
            self.assertEqual(application.municipality_id, self.municipality_id)
            self.assertEqual(
                application.status,
                VolunteerApplicationStatus.PENDING.value,
            )

            mine = await service.get_user_applications(
                db,
                self.user,
                UserApplicationListParams(page=1, limit=20),
            )
            self.assertEqual(mine["total"], 1)
            self.assertEqual(mine["items"][0].id, application.id)

            with self.assertRaises(HTTPException) as duplicate:
                await service.submit_application(
                    db,
                    self.user,
                    VolunteerApplicationCreate(
                        municipality_id=self.municipality_id
                    ),
                )
            self.assertEqual(duplicate.exception.status_code, 409)

            rejected = await service.reject_application(
                db,
                self.municipality,
                application.id,
            )
            self.assertEqual(
                rejected.status,
                VolunteerApplicationStatus.REJECTED.value,
            )

            reapplied = await service.submit_application(
                db,
                self.user,
                VolunteerApplicationCreate(
                    municipality_id=self.municipality_id
                ),
            )
            self.assertNotEqual(reapplied.id, application.id)
            self.assertEqual(
                reapplied.status,
                VolunteerApplicationStatus.PENDING.value,
            )

    async def test_unauthenticated_submission_dependency_rejects_request(
        self,
    ) -> None:
        async with AsyncSessionLocal() as db:
            with self.assertRaises(HTTPException) as unauthenticated:
                await auth_service.get_current_user(None, db)
        self.assertEqual(unauthenticated.exception.status_code, 401)

    async def test_municipality_lists_accepts_and_creates_membership(self) -> None:
        async with AsyncSessionLocal() as db:
            application = await service.submit_application(
                db,
                self.user,
                VolunteerApplicationCreate(
                    municipality_id=self.municipality_id
                ),
            )

            applications = await service.get_municipality_applications(
                db,
                self.municipality,
                MunicipalityApplicationListParams(
                    page=1,
                    limit=20,
                    status=VolunteerApplicationStatus.PENDING,
                ),
            )
            self.assertEqual(applications["total"], 1)
            self.assertEqual(applications["items"][0].id, application.id)

            with self.assertRaises(HTTPException) as wrong_owner:
                await service.accept_application(
                    db,
                    self.other_municipality,
                    application.id,
                )
            self.assertEqual(wrong_owner.exception.status_code, 404)

            accepted = await service.accept_application(
                db,
                self.municipality,
                application.id,
            )
            self.assertEqual(
                accepted["application"].status,
                VolunteerApplicationStatus.ACCEPTED.value,
            )
            self.assertEqual(accepted["volunteer"]["user_id"], self.user_id)

            membership = await service.get_user_volunteer(db, self.user)
            self.assertEqual(membership.user_id, self.user_id)
            self.assertEqual(membership.municipality_id, self.municipality_id)

            volunteers = await service.get_municipality_volunteers(
                db,
                self.municipality,
                MunicipalityVolunteerListParams(page=1, limit=20),
            )
            self.assertEqual(volunteers["total"], 1)
            self.assertEqual(volunteers["items"][0]["id"], membership.id)

            with self.assertRaises(HTTPException) as already_volunteer:
                await service.submit_application(
                    db,
                    self.user,
                    VolunteerApplicationCreate(
                        municipality_id=self.municipality_id
                    ),
                )
            self.assertEqual(already_volunteer.exception.status_code, 409)

    async def test_reject_is_owned_and_does_not_create_volunteer(self) -> None:
        async with AsyncSessionLocal() as db:
            application = await service.submit_application(
                db,
                self.second_user,
                VolunteerApplicationCreate(
                    municipality_id=self.municipality_id
                ),
            )
            with self.assertRaises(HTTPException) as wrong_owner:
                await service.reject_application(
                    db,
                    self.other_municipality,
                    application.id,
                )
            self.assertEqual(wrong_owner.exception.status_code, 404)

            rejected = await service.reject_application(
                db,
                self.municipality,
                application.id,
            )
            self.assertEqual(
                rejected.status,
                VolunteerApplicationStatus.REJECTED.value,
            )
            with self.assertRaises(HTTPException) as no_membership:
                await service.get_user_volunteer(db, self.second_user)
            self.assertEqual(no_membership.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
