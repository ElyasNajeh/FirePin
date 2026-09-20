from pydantic import BaseModel, ConfigDict

from app.features.fire_reports.schema import Latitude, Longitude


class RouteOrigin(BaseModel):
    latitude: Latitude
    longitude: Longitude

    model_config = ConfigDict(extra="forbid")


class RoutePoint(BaseModel):
    latitude: float
    longitude: float


class FireReportRouteResponse(BaseModel):
    geometry: list[RoutePoint]
    distance_km: float
    duration_seconds: int
