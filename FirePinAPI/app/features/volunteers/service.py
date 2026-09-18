import re

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.features.municipalities.model import Municipality
from app.features.users.model import User
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


def application_not_found() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Volunteer application not found",
    )


async def submit_application(
    db: AsyncSession,
    user: User,
    application_data: VolunteerApplicationCreate,
) -> VolunteerApplication:
    await db.execute(
        select(User.id).where(User.id == user.id).with_for_update()
    )

    municipality = await db.get(Municipality, application_data.municipality_id)
    if municipality is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Municipality not found",
        )
    if not municipality.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Municipality is inactive",
        )

    volunteer_result = await db.execute(
        select(Volunteer.id).where(Volunteer.user_id == user.id)
    )
    if volunteer_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User is already a volunteer",
        )

    pending_result = await db.execute(
        select(VolunteerApplication.id).where(
            VolunteerApplication.user_id == user.id,
            VolunteerApplication.status == VolunteerApplicationStatus.PENDING.value,
        )
    )
    if pending_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already has a pending volunteer application",
        )

    application = VolunteerApplication(
        user_id=user.id,
        municipality_id=municipality.id,
        status=VolunteerApplicationStatus.PENDING.value,
    )
    db.add(application)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already has a pending volunteer application",
        ) from None

    result = await db.execute(
        select(VolunteerApplication)
        .options(selectinload(VolunteerApplication.municipality))
        .where(VolunteerApplication.id == application.id)
    )
    return result.scalar_one()


async def get_user_applications(
    db: AsyncSession,
    user: User,
    params: UserApplicationListParams,
) -> dict:
    total_result = await db.execute(
        select(func.count(VolunteerApplication.id)).where(
            VolunteerApplication.user_id == user.id
        )
    )
    total = total_result.scalar_one()

    result = await db.execute(
        select(VolunteerApplication)
        .options(selectinload(VolunteerApplication.municipality))
        .where(VolunteerApplication.user_id == user.id)
        .order_by(VolunteerApplication.id.desc())
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }


async def get_user_volunteer(
    db: AsyncSession,
    user: User,
) -> Volunteer:
    result = await db.execute(
        select(Volunteer)
        .options(selectinload(Volunteer.municipality))
        .where(Volunteer.user_id == user.id)
    )
    volunteer = result.scalar_one_or_none()
    if volunteer is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Volunteer not found",
        )
    return volunteer


def identity_search_filter(search: str):
    search_pattern = f"%{search}%"
    compact_search = re.sub(r"[\s\-()]", "", search)
    compact_pattern = f"%{compact_search}%"
    return or_(
        User.full_name.ilike(search_pattern),
        User.phone.ilike(compact_pattern),
        User.national_id.ilike(compact_pattern),
    )


async def get_municipality_applications(
    db: AsyncSession,
    municipality: Municipality,
    params: MunicipalityApplicationListParams,
) -> dict:
    filters = [VolunteerApplication.municipality_id == municipality.id]

    if params.status is not None:
        filters.append(VolunteerApplication.status == params.status.value)
    if params.search:
        filters.append(identity_search_filter(params.search))

    total_result = await db.execute(
        select(func.count(VolunteerApplication.id))
        .join(User, User.id == VolunteerApplication.user_id)
        .where(*filters)
    )
    total = total_result.scalar_one()

    result = await db.execute(
        select(VolunteerApplication)
        .join(User, User.id == VolunteerApplication.user_id)
        .options(selectinload(VolunteerApplication.user))
        .where(*filters)
        .order_by(VolunteerApplication.id.desc())
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": list(result.scalars().all()),
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }


async def get_owned_application_for_update(
    db: AsyncSession,
    municipality: Municipality,
    application_id: int,
) -> VolunteerApplication:
    result = await db.execute(
        select(VolunteerApplication)
        .options(selectinload(VolunteerApplication.user))
        .where(
            VolunteerApplication.id == application_id,
            VolunteerApplication.municipality_id == municipality.id,
        )
        .with_for_update()
    )
    application = result.scalar_one_or_none()
    if application is None:
        raise application_not_found()
    return application


async def accept_application(
    db: AsyncSession,
    municipality: Municipality,
    application_id: int,
) -> dict:
    application = await get_owned_application_for_update(
        db,
        municipality,
        application_id,
    )
    if application.status != VolunteerApplicationStatus.PENDING.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Volunteer application is not pending",
        )

    await db.execute(
        select(User.id)
        .where(User.id == application.user_id)
        .with_for_update()
    )

    volunteer_result = await db.execute(
        select(Volunteer.id).where(Volunteer.user_id == application.user_id)
    )
    if volunteer_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User is already a volunteer",
        )

    application.status = VolunteerApplicationStatus.ACCEPTED.value
    volunteer = Volunteer(
        user_id=application.user_id,
        municipality_id=municipality.id,
    )
    db.add(volunteer)

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Volunteer application could not be accepted",
        ) from None

    application_result = await db.execute(
        select(VolunteerApplication)
        .options(selectinload(VolunteerApplication.user))
        .where(VolunteerApplication.id == application.id)
    )
    accepted_application = application_result.scalar_one()
    await db.refresh(volunteer)

    return {
        "application": accepted_application,
        "volunteer": volunteer_list_item(volunteer, accepted_application.user),
    }


async def reject_application(
    db: AsyncSession,
    municipality: Municipality,
    application_id: int,
) -> VolunteerApplication:
    application = await get_owned_application_for_update(
        db,
        municipality,
        application_id,
    )
    if application.status != VolunteerApplicationStatus.PENDING.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Volunteer application is not pending",
        )

    application.status = VolunteerApplicationStatus.REJECTED.value
    await db.commit()

    result = await db.execute(
        select(VolunteerApplication)
        .options(selectinload(VolunteerApplication.user))
        .where(VolunteerApplication.id == application.id)
    )
    return result.scalar_one()


def volunteer_list_item(volunteer: Volunteer, user: User) -> dict:
    return {
        "id": volunteer.id,
        "user_id": user.id,
        "full_name": user.full_name,
        "phone": user.phone,
        "national_id": user.national_id,
        "birth_date": user.birth_date,
        "created_at": volunteer.created_at,
    }


async def get_municipality_volunteers(
    db: AsyncSession,
    municipality: Municipality,
    params: MunicipalityVolunteerListParams,
) -> dict:
    filters = [Volunteer.municipality_id == municipality.id]
    if params.search:
        filters.append(identity_search_filter(params.search))

    total_result = await db.execute(
        select(func.count(Volunteer.id))
        .join(User, User.id == Volunteer.user_id)
        .where(*filters)
    )
    total = total_result.scalar_one()

    result = await db.execute(
        select(Volunteer, User)
        .join(User, User.id == Volunteer.user_id)
        .where(*filters)
        .order_by(Volunteer.id.desc())
        .offset((params.page - 1) * params.limit)
        .limit(params.limit)
    )

    return {
        "items": [
            volunteer_list_item(volunteer, applicant)
            for volunteer, applicant in result.all()
        ],
        "page": params.page,
        "limit": params.limit,
        "total": total,
    }
