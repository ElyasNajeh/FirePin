from datetime import datetime

from pydantic import BaseModel, ConfigDict


class NotificationEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    fire_report_id: int
    event_type: str
    title: str
    body: str
    created_at: datetime
