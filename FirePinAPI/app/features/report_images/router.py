from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Security, status
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db.session import get_db
from app.features.auth.service import (
    authentication_error,
    get_user_id_from_token,
)
from app.features.municipalities.model import Municipality
from app.features.municipalities.service import get_municipality_id_from_token
from app.features.report_images import service
from app.features.report_images.model import ReportImage
from app.features.users.model import User
from app.features.volunteers.model import Volunteer

router = APIRouter(tags=["Report Images"])
bearer_scheme = HTTPBearer(auto_error=False)


async def get_authorized_image(
    db: AsyncSession,
    credentials: HTTPAuthorizationCredentials | None,
    report_id: int,
    image_id: int,
) -> ReportImage:
    if credentials is None:
        raise authentication_error("Access token missing")

    token = credentials.credentials
    user_id = get_user_id_from_token(token, "access")
    municipality_id = get_municipality_id_from_token(token, "access")

    user = None
    municipality = None
    if user_id is not None:
        user = await db.get(User, user_id)
        if user is None:
            raise authentication_error("Invalid or expired access token")
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account is inactive",
            )
    elif municipality_id is not None:
        municipality = await db.get(Municipality, municipality_id)
        if municipality is None:
            raise authentication_error("Invalid or expired access token")
        if not municipality.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account is inactive",
            )
    else:
        raise authentication_error("Invalid or expired access token")

    result = await db.execute(
        select(ReportImage)
        .options(selectinload(ReportImage.report))
        .where(
            ReportImage.id == image_id,
            ReportImage.report_id == report_id,
        )
    )
    image = result.scalar_one_or_none()
    if image is None:
        raise image_not_found()

    if user is not None:
        if image.report.reporter_id != user.id:
            volunteer_result = await db.execute(
                select(Volunteer).where(Volunteer.user_id == user.id)
            )
            volunteer = volunteer_result.scalar_one_or_none()
            if (
                volunteer is None
                or volunteer.municipality_id != image.report.municipality_id
            ):
                raise image_not_found()
        return image

    if municipality is not None:
        if image.report.municipality_id != municipality.id:
            raise image_not_found()
        return image

    raise authentication_error("Invalid or expired access token")


def image_not_found() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Report image not found",
    )


@router.get(
    "/fire-reports/{report_id}/images/{image_id}",
    response_class=FileResponse,
    status_code=status.HTTP_200_OK,
)
async def get_report_image(
    report_id: Annotated[int, Path(gt=0)],
    image_id: Annotated[int, Path(gt=0)],
    credentials: HTTPAuthorizationCredentials | None = Security(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> FileResponse:
    image = await get_authorized_image(
        db,
        credentials,
        report_id,
        image_id,
    )
    path = service.resolve_image_path(image)
    return FileResponse(path, media_type=service.image_media_type(path))
