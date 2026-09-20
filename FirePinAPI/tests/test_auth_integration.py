import os
from datetime import date, datetime, timedelta, timezone
import unittest
from uuid import uuid4

from fastapi import HTTPException
from fastapi.routing import APIRoute
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import delete, select

from app.core.security import hash_password, hash_token
from app.db.session import AsyncSessionLocal, engine
from app.features.auth import service as auth_service
from app.features.auth.model import UserSession
from app.features.auth.schema import LoginRequest, RefreshTokenRequest
from app.features.device_tokens.model import DeviceToken  # noqa: F401
from app.features.fire_reports.model import FireReport  # noqa: F401
from app.features.municipalities import service as municipality_service
from app.features.municipalities.model import Municipality, MunicipalitySession
from app.features.municipalities.schema import MunicipalityLoginRequest
from app.features.report_images.model import ReportImage  # noqa: F401
from app.features.users import service as user_service
from app.features.users.model import User
from app.features.users.router import router as users_router
from app.features.users.schema import UserRegister
from app.features.volunteers.model import (  # noqa: F401
    Volunteer,
    VolunteerApplication,
)


def bearer(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


@unittest.skipUnless(
    os.getenv("FIREPIN_RUN_DB_TESTS") == "1",
    "Set FIREPIN_RUN_DB_TESTS=1 to run PostgreSQL integration tests",
)
class AuthenticationIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        suffix = str(uuid4().int % 1_000_000_000).zfill(9)
        self.national_id = suffix
        self.phone = f"059{suffix[:7]}"
        self.pin = "2468"
        self.email = f"auth-{uuid4().hex}@example.com"
        self.password = "municipality-password"

        async with AsyncSessionLocal() as db:
            self.user = await user_service.register_user(
                db,
                UserRegister(
                    full_name="Authentication Test User",
                    phone=self.phone,
                    national_id=self.national_id,
                    birth_date=date(1995, 4, 12),
                    pin=self.pin,
                ),
            )
            municipality = Municipality(
                name=f"Authentication municipality {uuid4().hex}",
                email=self.email,
                password_hash=hash_password(self.password),
                latitude="31.780000",
                longitude="35.240000",
            )
            db.add(municipality)
            await db.commit()
            await db.refresh(municipality)
            self.user_id = self.user.id
            self.municipality_id = municipality.id

    async def asyncTearDown(self) -> None:
        async with AsyncSessionLocal() as db:
            await db.execute(delete(User).where(User.id == self.user_id))
            await db.execute(
                delete(Municipality).where(
                    Municipality.id == self.municipality_id
                )
            )
            await db.commit()
        await engine.dispose()

    async def user_tokens(self) -> dict[str, str]:
        async with AsyncSessionLocal() as db:
            return await auth_service.login(
                db,
                LoginRequest(national_id=self.national_id, pin=self.pin),
            )

    async def municipality_tokens(self) -> dict[str, str]:
        async with AsyncSessionLocal() as db:
            return await municipality_service.login(
                db,
                MunicipalityLoginRequest(
                    email=self.email,
                    password=self.password,
                ),
            )

    async def test_user_national_id_login_and_bad_credentials(self) -> None:
        tokens = await self.user_tokens()
        self.assertTrue(tokens["access_token"])
        self.assertTrue(tokens["refresh_token"])

        async with AsyncSessionLocal() as db:
            with self.assertRaises(HTTPException) as caught:
                await auth_service.login(
                    db,
                    LoginRequest(national_id=self.national_id, pin="0000"),
                )
        self.assertEqual(caught.exception.status_code, 401)

    async def test_registration_conflicts(self) -> None:
        async with AsyncSessionLocal() as db:
            with self.assertRaises(HTTPException) as caught:
                await user_service.register_user(
                    db,
                    UserRegister(
                        full_name="Duplicate User",
                        phone=self.phone,
                        national_id=self.national_id,
                        birth_date=date(1994, 1, 1),
                        pin="1234",
                    ),
                )
        self.assertEqual(caught.exception.status_code, 409)

    async def test_user_me_refresh_and_logout(self) -> None:
        tokens = await self.user_tokens()
        async with AsyncSessionLocal() as db:
            current = await auth_service.get_current_user(
                bearer(tokens["access_token"]),
                db,
            )
            self.assertEqual(current.id, self.user_id)

            refreshed = await auth_service.refresh_access_token(
                RefreshTokenRequest(refresh_token=tokens["refresh_token"]),
                db,
            )
            self.assertTrue(refreshed["access_token"])

            await auth_service.logout(
                db,
                RefreshTokenRequest(refresh_token=tokens["refresh_token"]),
            )
            with self.assertRaises(HTTPException) as caught:
                await auth_service.refresh_access_token(
                    RefreshTokenRequest(
                        refresh_token=tokens["refresh_token"]
                    ),
                    db,
                )
            self.assertEqual(caught.exception.status_code, 401)

    async def test_invalid_expired_and_inactive_user_refresh(self) -> None:
        async with AsyncSessionLocal() as db:
            with self.assertRaises(HTTPException) as invalid:
                await auth_service.refresh_access_token(
                    RefreshTokenRequest(refresh_token="not-a-token"),
                    db,
                )
            self.assertEqual(invalid.exception.status_code, 401)

        tokens = await self.user_tokens()
        async with AsyncSessionLocal() as db:
            session = (
                await db.execute(
                    select(UserSession).where(
                        UserSession.refresh_token_hash
                        == hash_token(tokens["refresh_token"])
                    )
                )
            ).scalar_one()
            session.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
            await db.commit()
            with self.assertRaises(HTTPException) as expired:
                await auth_service.refresh_access_token(
                    RefreshTokenRequest(
                        refresh_token=tokens["refresh_token"]
                    ),
                    db,
                )
            self.assertEqual(expired.exception.status_code, 401)

        active_tokens = await self.user_tokens()
        async with AsyncSessionLocal() as db:
            user = await db.get(User, self.user_id)
            user.is_active = False
            await db.commit()
            with self.assertRaises(HTTPException) as inactive:
                await auth_service.refresh_access_token(
                    RefreshTokenRequest(
                        refresh_token=active_tokens["refresh_token"]
                    ),
                    db,
                )
            self.assertEqual(inactive.exception.status_code, 403)

    async def test_municipality_login_me_refresh_and_logout(self) -> None:
        tokens = await self.municipality_tokens()
        async with AsyncSessionLocal() as db:
            municipality = await municipality_service.get_current_municipality(
                bearer(tokens["access_token"]),
                db,
            )
            self.assertEqual(municipality.id, self.municipality_id)

            refreshed = await municipality_service.refresh_access_token(
                RefreshTokenRequest(refresh_token=tokens["refresh_token"]),
                db,
            )
            self.assertTrue(refreshed["access_token"])

            await municipality_service.logout(
                db,
                RefreshTokenRequest(refresh_token=tokens["refresh_token"]),
            )
            session = (
                await db.execute(
                    select(MunicipalitySession).where(
                        MunicipalitySession.refresh_token_hash
                        == hash_token(tokens["refresh_token"])
                    )
                )
            ).scalar_one()
            self.assertIsNotNone(session.revoked_at)

    async def test_wrong_account_type_authorization(self) -> None:
        user_tokens = await self.user_tokens()
        municipality_tokens = await self.municipality_tokens()
        async with AsyncSessionLocal() as db:
            with self.assertRaises(HTTPException) as user_rejected:
                await auth_service.get_current_user(
                    bearer(municipality_tokens["access_token"]),
                    db,
                )
            self.assertEqual(user_rejected.exception.status_code, 401)

            with self.assertRaises(HTTPException) as municipality_rejected:
                await municipality_service.get_current_municipality(
                    bearer(user_tokens["access_token"]),
                    db,
                )
            self.assertEqual(municipality_rejected.exception.status_code, 401)

    async def test_user_list_and_detail_require_user_authentication(self) -> None:
        protected_paths = {"/users", "/users/{user_id}"}
        routes = {
            route.path: route
            for route in users_router.routes
            if isinstance(route, APIRoute) and route.path in protected_paths
        }
        self.assertEqual(set(routes), protected_paths)
        for route in routes.values():
            dependency_calls = {
                dependency.call for dependency in route.dependant.dependencies
            }
            self.assertIn(auth_service.get_current_user, dependency_calls)

        async with AsyncSessionLocal() as db:
            with self.assertRaises(HTTPException) as missing:
                await auth_service.get_current_user(None, db)
            self.assertEqual(missing.exception.status_code, 401)


if __name__ == "__main__":
    unittest.main()
