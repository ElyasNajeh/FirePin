from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.features.auth.router import router as auth_router
from app.features.device_tokens.router import router as device_tokens_router
from app.features.fire_reports.router import router as fire_reports_router
from app.features.municipalities.router import router as municipalities_router
from app.features.notifications.router import router as notifications_router
from app.features.report_images.router import router as report_images_router
from app.features.users.router import router as users_router
from app.features.volunteers.router import router as volunteers_router

app = FastAPI(title=settings.APP_NAME)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(device_tokens_router)
app.include_router(users_router)
app.include_router(municipalities_router)
app.include_router(notifications_router)
app.include_router(volunteers_router)
app.include_router(fire_reports_router)
app.include_router(report_images_router)


@app.get("/")
def root() -> dict[str, str]:
    return {"message": f"{settings.APP_NAME} is running"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}
