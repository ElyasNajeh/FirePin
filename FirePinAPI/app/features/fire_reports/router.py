from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Path, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.features.auth.service import get_current_user
from app.features.fire_reports import service
from app.features.fire_reports.model import FireReport
from app.features.fire_reports.schema import (
    FireReportCreate,
    FireReportListParams,
    FireReportListResponse,
    FireReportResponse,
    Latitude,
    Longitude,
    MunicipalityFireReportListResponse,
    MunicipalityFireReportResponse,
)
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import get_current_municipality
from app.features.routing.schema import FireReportRouteResponse, RouteOrigin
from app.features.routing.service import routing_service
from app.features.users.model import User
from app.features.volunteers import service as volunteer_service
from app.features.volunteers.model import Volunteer

router = APIRouter(tags=["Fire Reports"])


async def get_current_volunteer(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Volunteer:
    return await volunteer_service.get_user_volunteer(db, user)


@router.post(
    "/fire-reports",
    response_model=FireReportResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_report(
    latitude: Annotated[Latitude, Form()],
    longitude: Annotated[Longitude, Form()],
    reporter: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    pin: Annotated[str | None, Form()] = None,
    images: Annotated[list[UploadFile] | None, File()] = None,
) -> FireReport:
    uploads = images or []
    try:
        return await service.create_report(
            db,
            reporter,
            FireReportCreate(latitude=latitude, longitude=longitude),
            uploads,
            pin,
        )
    finally:
        for upload in uploads:
            await upload.close()


@router.get(
    "/fire-reports/me",
    response_model=FireReportListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_my_reports(
    params: Annotated[FireReportListParams, Query()],
    reporter: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_user_reports(db, reporter, params)


@router.get(
    "/fire-reports/me/{report_id}",
    response_model=FireReportResponse,
    status_code=status.HTTP_200_OK,
)
async def get_my_report(
    report_id: Annotated[int, Path(gt=0)],
    reporter: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FireReport:
    return await service.get_user_report(db, reporter, report_id)


@router.get(
    "/volunteers/me/fire-reports",
    response_model=FireReportListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_volunteer_reports(
    params: Annotated[FireReportListParams, Query()],
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_volunteer_reports(db, volunteer, params)


@router.get(
    "/volunteers/me/fire-reports/{report_id}",
    response_model=FireReportResponse,
    status_code=status.HTTP_200_OK,
)
async def get_volunteer_report(
    report_id: Annotated[int, Path(gt=0)],
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> FireReport:
    return await service.get_volunteer_report(db, volunteer, report_id)


@router.post(
    "/volunteers/me/fire-reports/{report_id}/route",
    response_model=FireReportRouteResponse,
    status_code=status.HTTP_200_OK,
)
async def get_volunteer_report_route(
    origin: RouteOrigin,
    report_id: Annotated[int, Path(gt=0)],
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> dict:
    report = await service.get_volunteer_report(db, volunteer, report_id)
    return await routing_service.route(
        origin.latitude,
        origin.longitude,
        report.latitude,
        report.longitude,
    )


@router.post(
    "/volunteers/me/fire-reports/{report_id}/claim",
    response_model=FireReportResponse,
    status_code=status.HTTP_200_OK,
)
async def claim_report(
    report_id: Annotated[int, Path(gt=0)],
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> FireReport:
    return await service.claim_report(db, volunteer, report_id)


@router.post(
    "/volunteers/me/fire-reports/{report_id}/resolve",
    response_model=FireReportResponse,
    status_code=status.HTTP_200_OK,
)
async def resolve_report(
    report_id: Annotated[int, Path(gt=0)],
    volunteer: Volunteer = Depends(get_current_volunteer),
    db: AsyncSession = Depends(get_db),
) -> FireReport:
    return await service.resolve_report(db, volunteer, report_id)


@router.get(
    "/municipalities/auth/fire-reports",
    response_model=MunicipalityFireReportListResponse,
    status_code=status.HTTP_200_OK,
)
async def get_municipality_reports(
    params: Annotated[FireReportListParams, Query()],
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> dict:
    return await service.get_municipality_reports(db, municipality, params)


@router.get(
    "/municipalities/auth/fire-reports/{report_id}",
    response_model=MunicipalityFireReportResponse,
    status_code=status.HTTP_200_OK,
)
async def get_municipality_report(
    report_id: Annotated[int, Path(gt=0)],
    municipality: Municipality = Depends(get_current_municipality),
    db: AsyncSession = Depends(get_db),
) -> FireReport:
    return await service.get_municipality_report(db, municipality, report_id)
