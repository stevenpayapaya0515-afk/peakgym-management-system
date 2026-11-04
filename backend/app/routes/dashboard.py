
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.members import Member
from app.models.memberships import Membership
from app.models.user import User
from app.routes.auth import get_current_user


router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"]
)


@router.get("/summary")
def get_dashboard_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    today = date.today()

    total_members = db.query(Member).count()

    active_memberships = db.query(Membership).filter(
        Membership.start_date <= today,
        Membership.due_date >= today
    ).count()

    expired_memberships = db.query(Membership).filter(
        Membership.due_date < today
    ).count()

    upcoming_memberships = db.query(Membership).filter(
        Membership.start_date > today
    ).count()

    members_without_membership = (
        db.query(Member)
        .outerjoin(
            Membership,
            Member.id == Membership.member_id
        )
        .filter(Membership.id.is_(None))
        .count()
    )

    return {
        "total_members": total_members,
        "active_memberships": active_memberships,
        "expired_memberships": expired_memberships,
        "upcoming_memberships": upcoming_memberships,
        "members_without_membership": members_without_membership
    }
