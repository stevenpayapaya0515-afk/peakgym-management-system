from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.routes.auth import router as auth_router
from app.routes.login_otp import router as login_otp_router
from app.routes.users import router as users_router
from app.routes.members import router as members_router
from app.routes.memberships import router as memberships_router
from app.routes.dashboard import router as dashboard_router
from app.routes.settings import router as settings_router
from app.routes.settings import router as settings_router
from app.routes.invitations import router as invitations_router
from app.routes.registration import router as registration_router
from app.routes.registration_activation import router as registration_activation_router
from app.routes.security_dashboard import router as security_dashboard_router
from app.routes.password_recovery import router as password_recovery_router


app = FastAPI(
    title="PeakGym Management System API",
    description="Backend API for PeakGym Management System",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

app.include_router(auth_router)
app.include_router(login_otp_router)
app.include_router(users_router)
app.include_router(members_router)
app.include_router(memberships_router)
app.include_router(dashboard_router)
app.include_router(settings_router)
app.include_router(invitations_router)
app.include_router(registration_router)
app.include_router(registration_activation_router)
app.include_router(security_dashboard_router)
app.include_router(password_recovery_router)

@app.get("/")
def root():
    return {
        "message": "Welcome to PeakGym Management System API",
        "status": "ok"
    }


@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "application": "PeakGym Management System"
    }


@app.get("/database-test")
def database_test(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))

        return {
            "status": "connected",
            "database": "security_1",
            "message": "MySQL connection successful"
        }

    except Exception:
        raise HTTPException(
            status_code=500,
            detail="Database connection failed"
        )