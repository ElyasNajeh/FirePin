import asyncio
import json
import socket
from collections.abc import Callable
from dataclasses import dataclass
from decimal import Decimal
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from fastapi import HTTPException, status

from app.core.config import settings


@dataclass(frozen=True)
class RoutingProviderResponse:
    status_code: int
    body: bytes


ProviderRequest = Callable[[str, bytes, float], RoutingProviderResponse]


def _provider_request(
    url: str,
    payload: bytes,
    timeout_seconds: float,
) -> RoutingProviderResponse:
    request = Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=timeout_seconds) as response:
        return RoutingProviderResponse(response.status, response.read())


def decode_polyline6(encoded: str) -> list[dict[str, float]]:
    coordinates: list[dict[str, float]] = []
    index = 0
    latitude = 0
    longitude = 0

    while index < len(encoded):
        deltas = []
        for _ in range(2):
            result = 0
            shift = 0
            while True:
                if index >= len(encoded):
                    raise ValueError("Invalid route geometry")
                value = ord(encoded[index]) - 63
                index += 1
                result |= (value & 0x1F) << shift
                shift += 5
                if value < 0x20:
                    break
            deltas.append(~(result >> 1) if result & 1 else result >> 1)
        latitude += deltas[0]
        longitude += deltas[1]
        coordinates.append(
            {
                "latitude": latitude / 1_000_000,
                "longitude": longitude / 1_000_000,
            }
        )

    return coordinates


class ValhallaRoutingService:
    def __init__(
        self,
        base_url: str | None = None,
        timeout_seconds: float | None = None,
        provider_request: ProviderRequest = _provider_request,
    ) -> None:
        self.base_url = (base_url or settings.VALHALLA_BASE_URL).rstrip("/")
        self.timeout_seconds = (
            timeout_seconds
            if timeout_seconds is not None
            else settings.VALHALLA_TIMEOUT_SECONDS
        )
        self.provider_request = provider_request

    async def route(
        self,
        origin_latitude: Decimal,
        origin_longitude: Decimal,
        destination_latitude: Decimal,
        destination_longitude: Decimal,
    ) -> dict:
        payload = json.dumps(
            {
                "locations": [
                    {
                        "lat": float(origin_latitude),
                        "lon": float(origin_longitude),
                    },
                    {
                        "lat": float(destination_latitude),
                        "lon": float(destination_longitude),
                    },
                ],
                "costing": "auto",
                "units": "kilometers",
            }
        ).encode("utf-8")

        try:
            response = await asyncio.to_thread(
                self.provider_request,
                f"{self.base_url}/route",
                payload,
                self.timeout_seconds,
            )
        except (TimeoutError, socket.timeout):
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail="Routing provider timed out",
            ) from None
        except HTTPError as error:
            if 400 <= error.code < 500:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail="No driving route was found",
                ) from None
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Routing provider is unavailable",
            ) from None
        except (OSError, URLError):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Routing provider is unavailable",
            ) from None

        if response.status_code >= 500:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Routing provider is unavailable",
            )
        if response.status_code >= 400:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="No driving route was found",
            )

        try:
            data = json.loads(response.body)
            trip = data["trip"]
            legs = trip["legs"]
            summary = trip["summary"]
            geometry = [
                point
                for leg in legs
                for point in decode_polyline6(leg["shape"])
            ]
            distance = float(summary["length"])
            duration = round(float(summary["time"]))
            if len(geometry) < 2 or distance < 0 or duration < 0:
                raise ValueError
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="No driving route was found",
            ) from None

        return {
            "geometry": geometry,
            "distance_km": distance,
            "duration_seconds": duration,
        }


routing_service = ValhallaRoutingService()
