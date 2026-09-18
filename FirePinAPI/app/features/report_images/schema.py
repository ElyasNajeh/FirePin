from pydantic import BaseModel, ConfigDict


class ReportImageResponse(BaseModel):
    id: int
    url: str

    model_config = ConfigDict(from_attributes=True)
