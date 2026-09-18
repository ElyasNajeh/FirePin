import asyncio
from dataclasses import dataclass
from io import BytesIO
import mimetypes
from pathlib import Path
import re
import shutil
from uuid import uuid4

from fastapi import HTTPException, UploadFile, status
from PIL import Image, ImageSequence, UnidentifiedImageError
from pillow_heif import register_heif_opener

from app.core.config import settings
from app.features.report_images.model import ReportImage

register_heif_opener()
Image.init()

MAX_REPORT_IMAGES = 5
SAFE_EXTENSION_PATTERN = re.compile(r"^\.[a-z0-9]{1,10}$")
PREFERRED_EXTENSIONS = {
    "AVIF": ".avif",
    "GIF": ".gif",
    "HEIC": ".heic",
    "HEIF": ".heic",
    "JPEG": ".jpg",
    "PNG": ".png",
    "TIFF": ".tiff",
    "WEBP": ".webp",
}
PREFERRED_MEDIA_TYPES = {
    ".avif": "image/avif",
    ".gif": "image/gif",
    ".heic": "image/heic",
    ".heif": "image/heif",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".tif": "image/tiff",
    ".tiff": "image/tiff",
    ".webp": "image/webp",
}


@dataclass(frozen=True)
class ValidatedImage:
    data: bytes
    extension: str


def invalid_image_error() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail="Uploaded file is not a valid supported image",
    )


def extension_for_format(image_format: str) -> str:
    normalized_format = image_format.upper()
    extension = PREFERRED_EXTENSIONS.get(normalized_format)

    if extension is None:
        extension = next(
            (
                registered_extension.lower()
                for registered_extension, registered_format in Image.registered_extensions().items()
                if registered_format.upper() == normalized_format
            ),
            None,
        )

    if extension is None or not SAFE_EXTENSION_PATTERN.fullmatch(extension):
        raise invalid_image_error()
    return extension


def validate_image_bytes(data: bytes) -> ValidatedImage:
    if not data:
        raise invalid_image_error()

    try:
        with Image.open(BytesIO(data)) as image:
            image_format = image.format
            if image_format is None:
                raise invalid_image_error()
            image.verify()

        with Image.open(BytesIO(data)) as image:
            for frame in ImageSequence.Iterator(image):
                frame.load()
    except HTTPException:
        raise
    except (
        Image.DecompressionBombError,
        OSError,
        RuntimeError,
        SyntaxError,
        UnidentifiedImageError,
        ValueError,
    ):
        raise invalid_image_error() from None

    return ValidatedImage(
        data=data,
        extension=extension_for_format(image_format),
    )


async def validate_uploads(uploads: list[UploadFile]) -> list[ValidatedImage]:
    if len(uploads) > MAX_REPORT_IMAGES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="A fire report can contain at most 5 images",
        )

    validated_images = []
    for upload in uploads:
        try:
            data = await upload.read()
        except OSError:
            raise invalid_image_error() from None
        validated_images.append(validate_image_bytes(data))
    return validated_images


def upload_root() -> Path:
    return settings.UPLOAD_ROOT.resolve()


def report_directory(report_id: int) -> Path:
    root = upload_root()
    directory = (root / "fire_reports" / str(report_id)).resolve()
    try:
        directory.relative_to(root)
    except ValueError:
        raise RuntimeError("Invalid report upload directory") from None
    return directory


def save_images(report_id: int, images: list[ValidatedImage]) -> list[str]:
    if not images:
        return []

    directory = report_directory(report_id)
    directory.mkdir(parents=True, exist_ok=False)
    relative_paths = []

    for image in images:
        filename = f"{uuid4().hex}{image.extension}"
        destination = directory / filename
        with destination.open("xb") as image_file:
            image_file.write(image.data)
        relative_paths.append(destination.relative_to(upload_root()).as_posix())

    return relative_paths


async def save_report_images(
    report_id: int,
    images: list[ValidatedImage],
) -> list[str]:
    return await asyncio.to_thread(save_images, report_id, images)


def remove_report_directory(report_id: int) -> None:
    directory = report_directory(report_id)
    if directory.exists():
        shutil.rmtree(directory)


async def cleanup_report_images(report_id: int) -> None:
    await asyncio.to_thread(remove_report_directory, report_id)


def resolve_image_path(image: ReportImage) -> Path:
    root = upload_root()
    path = (root / image.image_path).resolve()
    try:
        path.relative_to(root)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Report image not found",
        ) from None

    if not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Report image not found",
        )
    return path


def image_media_type(path: Path) -> str:
    return (
        PREFERRED_MEDIA_TYPES.get(path.suffix.lower())
        or mimetypes.guess_type(path.name)[0]
        or "application/octet-stream"
    )
