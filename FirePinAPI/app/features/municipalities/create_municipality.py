import argparse
import asyncio
from getpass import getpass
import sys

from fastapi import HTTPException
from pydantic import ValidationError

from app.db.session import AsyncSessionLocal
from app.features.device_tokens.model import DeviceToken  # noqa: F401
from app.features.fire_reports.model import FireReport  # noqa: F401
from app.features.municipalities.schema import MunicipalityCreate
from app.features.municipalities.service import create_municipality
from app.features.report_images.model import ReportImage  # noqa: F401
from app.features.volunteers.model import (  # noqa: F401
    Volunteer,
    VolunteerApplication,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create an internal FirePin municipality account."
    )
    parser.add_argument("--name", required=True)
    parser.add_argument("--email", required=True)
    parser.add_argument("--latitude", required=True)
    parser.add_argument("--longitude", required=True)
    return parser.parse_args()


async def save_municipality(data: MunicipalityCreate) -> None:
    async with AsyncSessionLocal() as db:
        municipality = await create_municipality(db, data)
        print(
            "Municipality created: "
            f"id={municipality.id}, name={municipality.name}, "
            f"email={municipality.email}"
        )


def main() -> None:
    args = parse_args()
    password = getpass("Password: ")
    password_confirmation = getpass("Confirm password: ")

    if password != password_confirmation:
        print("Error: passwords do not match", file=sys.stderr)
        raise SystemExit(1)

    try:
        data = MunicipalityCreate(
            name=args.name,
            email=args.email,
            password=password,
            latitude=args.latitude,
            longitude=args.longitude,
        )
        asyncio.run(save_municipality(data))
    except ValidationError as error:
        for item in error.errors(include_input=False):
            field = ".".join(str(part) for part in item["loc"])
            print(f"Error: {field}: {item['msg']}", file=sys.stderr)
        raise SystemExit(1) from None
    except HTTPException as error:
        print(f"Error: {error.detail}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
