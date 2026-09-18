from math import asin, cos, radians, sin, sqrt

from fastapi import HTTPException, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.security import verify_password
from app.features.fire_reports.model import FireReport, FireReportStatus
from app.features.fire_reports.schema import FireReportCreate, FireReportListParams
from app.features.municipalities.model import Municipality
from app.features.notifications import service as notification_service
from app.features.report_images import service as image_service
from app.features.report_images.model import ReportImage
from app.features.users.model import User
from app.features.volunteers.model import Volunteer

EARTH_RADIUS_KM = 6371.0088


def report_not_found() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Fire report not found",
    )


def haversine_distance(
    latitude_a: float,
    longitude_a: float,
    latitude_b: float,
    longitude_b: float,
) -> float:
    latitude_delta = radians(latitude_b - latitude_a)
    longitude_delta = radians(longitude_b - longitude_a)
    latitude_a_radians = radians(latitude_a)
    latitude_b_radians = radians(latitude_b)

    haversine = (
        sin(latitude_delta / 2) ** 2
        + cos(latitude_a_radians)
        * cos(latitude_b_radians)
        * sin(longitude_delta / 2) ** 2
    )
    return 2 * EARTH_RADIUS_KM * asin(sqrt(min(1, haversine)))


def report_load_options(include_reporter: bool = False) -> list:
    options = [
        selectinload(FireReport.municipality),
        selectinload(FireReport.assigned_volunteer).selectinload(Volunteer.user),
        selectinload(FireReport.images),
    ]
    if include_reporter:
        options.append(selectinload(FireReport.reporter))
    return options


async def load_report(
    db: AsyncSession,
    report_id: int,
    include_reporter: bool = False,
) -> FireReport:
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options(include_reporter))
        .where(FireReport.id == report_id)
    )
    return result.scalar_one()


async def find_nearest_active_municipality(
    db: AsyncSession,
    latitude: float,
    longitude: float,
) -> Municipality:
    result = await db.execute(
        select(Municipality)
        .where(Municipality.is_active.is_(True))
        .order_by(Municipality.id)
    )
    municipalities = list(result.scalars().all())

    if not municipalities:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No active municipalities are available",
        )

    return min(
        municipalities,
        key=lambda municipality: haversine_distance(
            latitude,
            longitude,
            float(municipality.latitude),
            float(municipality.longitude),
        ),
    )


async def create_report(
    db: AsyncSession,
    reporter: User,
    report_data: FireReportCreate,
    uploads: list[UploadFile],
    pin: str | None,
) -> FireReport:
    validated_images = await image_service.validate_uploads(uploads)

    if not validated_images:
        if not pin:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="PIN is required when no images are provided",
            )
        if not verify_password(pin, reporter.pin_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="PIN verification failed",
            )

    municipality = await find_nearest_active_municipality(
        db,
        float(report_data.latitude),
        float(report_data.longitude),
    )

    report = FireReport(
        reporter_id=reporter.id,
        municipality_id=municipality.id,
        latitude=report_data.latitude,
        longitude=report_data.longitude,
        status=FireReportStatus.PENDING.value,
        assigned_volunteer_id=None,
    )
    db.add(report)

    report_id: int | None = None
    try:
        await db.flush()
        report_id = report.id

        image_paths = await image_service.save_report_images(
            report.id,
            validated_images,
        )
        db.add_all(
            [
                ReportImage(report_id=report.id, image_path=image_path)
                for image_path in image_paths
            ]
        )
        await db.commit()
    except Exception as error:
        await db.rollback()
        if report_id is not None and validated_images:
            try:
                await image_service.cleanup_report_images(report_id)
            except OSError:
                pass
        if isinstance(error, HTTPException):
            raise
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to create fire report",
        ) from None

    created_report = await load_report(db, report.id)
    await notification_service.notify_report_created(created_report)
    return created_report


async def get_user_reports(
    db: AsyncSession,
    reporter: User,
    params: FireReportListParams,
) -> dict:
    filters = [FireReport.reporter_id == reporter.id]
    if params.status is not None:
        filters.append(FireReport.status == params.status.value)

    total = (
        await db.execute(select(func.count(FireReport.id)).where(*filters))
    ).scalar_one()
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options())
        .where(*filters)
        .order_by(FireReport.id.desc())
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }


async def get_user_report(
    db: AsyncSession,
    reporter: User,
    report_id: int,
) -> FireReport:
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options())
        .where(
            FireReport.id == report_id,
            FireReport.reporter_id == reporter.id,
        )
    )
    report = result.scalar_one_or_none()
    if report is None:
        raise report_not_found()
    return report


async def get_volunteer_reports(
    db: AsyncSession,
    volunteer: Volunteer,
    params: FireReportListParams,
) -> dict:
    filters = [FireReport.municipality_id == volunteer.municipality_id]
    if params.status is not None:
        filters.append(FireReport.status == params.status.value)

    total = (
        await db.execute(select(func.count(FireReport.id)).where(*filters))
    ).scalar_one()
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options())
        .where(*filters)
        .order_by(FireReport.id.desc())
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }


async def get_volunteer_report(
    db: AsyncSession,
    volunteer: Volunteer,
    report_id: int,
) -> FireReport:
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options())
        .where(
            FireReport.id == report_id,
            FireReport.municipality_id == volunteer.municipality_id,
        )
    )
    report = result.scalar_one_or_none()
    if report is None:
        raise report_not_found()
    return report


async def get_volunteer_report_for_update(
    db: AsyncSession,
    volunteer: Volunteer,
    report_id: int,
) -> FireReport:
    result = await db.execute(
        select(FireReport)
        .where(
            FireReport.id == report_id,
            FireReport.municipality_id == volunteer.municipality_id,
        )
        .with_for_update()
    )
    report = result.scalar_one_or_none()
    if report is None:
        raise report_not_found()
    return report


async def claim_report(
    db: AsyncSession,
    volunteer: Volunteer,
    report_id: int,
) -> FireReport:
    report = await get_volunteer_report_for_update(db, volunteer, report_id)
    if (
        report.status != FireReportStatus.PENDING.value
        or report.assigned_volunteer_id is not None
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Fire report is not available to claim",
        )

    report.status = FireReportStatus.ASSIGNED.value
    report.assigned_volunteer_id = volunteer.id
    await db.commit()

    claimed_report = await load_report(db, report.id)
    await notification_service.notify_report_claimed(claimed_report)
    return claimed_report


async def resolve_report(
    db: AsyncSession,
    volunteer: Volunteer,
    report_id: int,
) -> FireReport:
    report = await get_volunteer_report_for_update(db, volunteer, report_id)
    if report.status != FireReportStatus.ASSIGNED.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Fire report is not assigned",
        )
    if report.assigned_volunteer_id != volunteer.id:
        raise report_not_found()

    report.status = FireReportStatus.RESOLVED.value
    await db.commit()

    resolved_report = await load_report(db, report.id)
    await notification_service.notify_report_resolved(resolved_report)
    return resolved_report


async def get_municipality_reports(
    db: AsyncSession,
    municipality: Municipality,
    params: FireReportListParams,
) -> dict:
    filters = [FireReport.municipality_id == municipality.id]
    if params.status is not None:
        filters.append(FireReport.status == params.status.value)

    total = (
        await db.execute(select(func.count(FireReport.id)).where(*filters))
    ).scalar_one()
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options(include_reporter=True))
        .where(*filters)
        .order_by(FireReport.id.desc())
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }


async def get_municipality_report(
    db: AsyncSession,
    municipality: Municipality,
    report_id: int,
) -> FireReport:
    result = await db.execute(
        select(FireReport)
        .options(*report_load_options(include_reporter=True))
        .where(
            FireReport.id == report_id,
            FireReport.municipality_id == municipality.id,
        )
    )
    report = result.scalar_one_or_none()
    if report is None:
        raise report_not_found()
    return report
