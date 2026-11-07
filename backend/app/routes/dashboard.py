from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, case, func
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


# =========================
# EXISTING DASHBOARD SUMMARY
# =========================
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


# =========================
# ADMIN DASHBOARD SUMMARY
# =========================
@router.get("/admin-summary")
def get_admin_dashboard_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Admin access required"
        )

    today = date.today()
    
    # STAFF COUNTS
    total_staff = db.query(User).filter(
        User.role == "staff"
    ).count()

    active_staff = db.query(User).filter(
        User.role == "staff",
        User.is_active == 1
    ).count()

    inactive_staff = db.query(User).filter(
        User.role == "staff",
        User.is_active == 0
    ).count()

    # MEMBERSHIP SUMMARY PER MEMBER
    membership_summary = (
        db.query(
            Membership.member_id.label("member_id"),

            func.max(
                Membership.due_date
            ).label("last_due"),

            func.max(
                case(
                    (
                        and_(
                            Membership.start_date <= today,
                            Membership.due_date >= today
                        ),
                        1
                    ),
                    else_=0
                )
            ).label("is_active"),

            func.max(
                case(
                    (
                        and_(
                            Membership.start_date <= today,
                            Membership.due_date == today
                        ),
                        1
                    ),
                    else_=0
                )
            ).label("expires_today")
        )
        .group_by(Membership.member_id)
        .subquery()
    )

    total_members = db.query(Member).count()

    active_members = db.query(
        membership_summary.c.member_id
    ).filter(
        membership_summary.c.is_active == 1
    ).count()

    expiring_today = db.query(
        membership_summary.c.member_id
    ).filter(
        membership_summary.c.expires_today == 1
    ).count()

    expired_members = db.query(
        membership_summary.c.member_id
    ).filter(
        membership_summary.c.last_due < today
    ).count()

    return {
        "total_staff": total_staff,
        "active_staff": active_staff,
        "inactive_staff": inactive_staff,
        "total_members": total_members,
        "active_memberships": active_members,
        "expiring_today": expiring_today,
        "expired_memberships": expired_members,
        "as_of": today.isoformat()
    }

# =========================
# STAFF DASHBOARD SUMMARY
# =========================
@router.get("/staff-summary")
def get_staff_dashboard_summary(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role != "staff":
        raise HTTPException(
            status_code=403,
            detail="Staff access required"
        )

    # get_current_user already rejects inactive staff accounts.
    today = date.today()

    # Count each member once, even when they have renewal history.
    membership_summary = (
        db.query(
            Membership.member_id.label("member_id"),
            func.max(Membership.due_date).label("last_due"),
            func.max(
                case(
                    (
                        and_(
                            Membership.start_date <= today,
                            Membership.due_date >= today
                        ),
                        1
                    ),
                    else_=0
                )
            ).label("is_active"),
            func.max(
                case(
                    (
                        and_(
                            Membership.start_date <= today,
                            Membership.due_date == today
                        ),
                        1
                    ),
                    else_=0
                )
            ).label("expires_today")
        )
        .group_by(Membership.member_id)
        .subquery()
    )

    total_members = db.query(Member).count()

    active_members = (
        db.query(membership_summary.c.member_id)
        .filter(membership_summary.c.is_active == 1)
        .count()
    )

    expiring_today = (
        db.query(membership_summary.c.member_id)
        .filter(membership_summary.c.expires_today == 1)
        .count()
    )

    expired_members = (
        db.query(membership_summary.c.member_id)
        .filter(membership_summary.c.last_due < today)
        .count()
    )

    return {
        "user": {
            "id": current_user.id,
            "username": current_user.username,
            "email": current_user.email,
            "role": current_user.role
        },
        "total_members": total_members,
        "active_memberships": active_members,
        "expiring_today": expiring_today,
        "expired_memberships": expired_members,
        "as_of": today.isoformat()
    }