from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.features.auth.service import get_current_user
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import get_current_municipality
from app.features.users.model import User
from app.features.volunteers import service
from app.features.volunteers.model import Volunteer, VolunteerApplication
from app.features.volunteers.schema import (
    AcceptApplicationResponse,
    MunicipalityApplicationListParams,
    MunicipalityVolunteerApplicationListResponse,
    MunicipalityVolunteerApplicationResponse,
    MunicipalityVolunteerListParams,
    MunicipalityVolunteerListResponse,
    UserApplicationListParams,
    UserVolunteerApplicationListResponse,
    UserVolunteerApplicationResponse,
    VolunteerApplicationCreate,
    VolunteerMeResponse,
)

router = APIRouter(tags=["Volunteers"])


@router.post(
    "/volunteer-applications",
    response_model=UserVolunteerApplicationResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_application(
    application_data: VolunteerApplicationCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> VolunteerApplication:
    return await service.submit_application(db, user, application_data)


@router.get(
    "/volunteer-applications/me",
    response_model=UserVolunteerApplicationListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_my_applications(
    params: Annotated[UserApplicationListParams, Query()],
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_user_applications(db, user, params)


@router.get(
    "/volunteers/me",
    response_model=VolunteerMeResponse,
    status_code=status.HTTP_200_OK,
)
async def get_my_volunteer_membership(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Volunteer:
    return await service.get_user_volunteer(db, user)


@router.get(
    "/municipalities/auth/volunteer-applications",
    response_model=MunicipalityVolunteerApplicationListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_municipality_applications(
    params: Annotated[MunicipalityApplicationListParams, Query()],
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_municipality_applications(
        db,
        municipality,
        params,
    )


@router.post(
    "/municipalities/auth/volunteer-applications/{application_id}/accept",
    response_model=AcceptApplicationResponse,
    status_code=status.HTTP_200_OK,
)
async def accept_application(
    application_id: Annotated[int, Path(gt=0)],
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.accept_application(db, municipality, application_id)


@router.post(
    "/municipalities/auth/volunteer-applications/{application_id}/reject",
    response_model=MunicipalityVolunteerApplicationResponse,
    status_code=status.HTTP_200_OK,
)
async def reject_application(
    application_id: Annotated[int, Path(gt=0)],
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> VolunteerApplication:
    return await service.reject_application(db, municipality, application_id)


@router.get(
    "/municipalities/auth/volunteers",
    response_model=MunicipalityVolunteerListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_municipality_volunteers(
    params: Annotated[MunicipalityVolunteerListParams, Query()],
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_municipality_volunteers(db, municipality, params)
