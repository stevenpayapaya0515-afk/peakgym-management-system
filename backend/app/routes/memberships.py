from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.members import Member
from app.models.memberships import Membership
from app.models.user import User
from app.routes.auth import get_current_user

import calendar
from app.schemas.memberships import MembershipUpdate, MembershipRenew

router = APIRouter(
    prefix="/memberships",
    tags=["Membership Management"]
)


def calculate_due_date(start_date: date) -> date:
    if start_date.month == 12:
        next_year = start_date.year + 1
        next_month = 1
    else:
        next_year = start_date.year
        next_month = start_date.month + 1

    last_day = calendar.monthrange(next_year, next_month)[1]
    day = min(start_date.day, last_day)

    return date(next_year, next_month, day)


@router.get("/")
def get_memberships(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    memberships = (
        db.query(Membership, Member)
        .join(Member, Membership.member_id == Member.id)
        .order_by(Membership.id.desc())
        .all()
    )

    today = date.today()

    results = []

    for membership, member in memberships:

        if membership.start_date > today:
            status = "Upcoming"
        elif membership.due_date >= today:
            status = "Active"
        else:
            status = "Expired"

        results.append({
            "id": membership.id,
            "member_id": member.id,
            "full_name": member.full_name,
            "start_date": membership.start_date,
            "due_date": membership.due_date,
            "status": status,
            "created_at": membership.created_at
        })

    return results


@router.get("/member/{member_id}/history")
def get_member_membership_history(
    member_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    member = db.query(Member).filter(
        Member.id == member_id
    ).first()

    if not member:
        raise HTTPException(
            status_code=404,
            detail="Member not found"
        )

    memberships = (
        db.query(Membership)
        .filter(Membership.member_id == member_id)
        .order_by(Membership.start_date.desc())
        .all()
    )

    today = date.today()
    results = []

    for membership in memberships:
        if membership.start_date > today:
            status = "Upcoming"
        elif membership.due_date >= today:
            status = "Active"
        else:
            status = "Expired"

        results.append({
            "id": membership.id,
            "member_id": member.id,
            "full_name": member.full_name,
            "start_date": membership.start_date,
            "due_date": membership.due_date,
            "status": status,
            "created_at": membership.created_at
        })

    return {
        "member_id": member.id,
        "full_name": member.full_name,
        "total_memberships": len(results),
        "history": results
    }

@router.put("/{membership_id}")
def update_membership(
    membership_id: int,
    membership_data: MembershipUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    # Validate start date
    if not date(1900, 1, 1) <= membership_data.start_date <= date(2099, 12, 31):
        raise HTTPException(
            status_code=422,
            detail="Start date must be between 1900-01-01 and 2099-12-31"
        )

    # Validate due date
    if not membership_data.start_date <= membership_data.due_date <= date(2100, 12, 31):
        raise HTTPException(
            status_code=422,
            detail="Due date must be on or after the start date and no later than 2100-12-31"
        )

    # Check if member exists
    member = db.query(Member).filter(
        Member.id == membership_data.member_id
    ).first()

    if not member:
        raise HTTPException(
            status_code=404,
            detail="Member not found"
        )

    # Check if membership belongs to the selected member
    membership = db.query(Membership).filter(
        Membership.id == membership_id,
        Membership.member_id == membership_data.member_id
    ).first()

    if not membership:
        raise HTTPException(
            status_code=404,
            detail="Membership not found for this member"
        )

    # Prevent overlapping membership periods
    overlapping = db.query(Membership).filter(
        Membership.member_id == membership_data.member_id,
        Membership.id != membership_id,
        Membership.start_date <= membership_data.due_date,
        Membership.due_date >= membership_data.start_date
    ).first()

    if overlapping:
        raise HTTPException(
            status_code=409,
            detail="Membership dates overlap with another membership period"
        )

    # Update membership
    membership.start_date = membership_data.start_date
    membership.due_date = membership_data.due_date

    try:
        db.commit()
        db.refresh(membership)

    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to update membership. Please try again."
        )

    return {
        "message": "Membership updated successfully",
        "membership": {
            "id": membership.id,
            "member_id": membership.member_id,
            "start_date": membership.start_date,
            "due_date": membership.due_date
        }
    }


@router.post("/renew")
def renew_membership(
    renewal_data: MembershipRenew,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    if not date(1900, 1, 1) <= renewal_data.start_date <= date(2099, 12, 31):
        raise HTTPException(
            status_code=422,
            detail="Start date must be between 1900-01-01 and 2099-12-31"
        )

    member = db.query(Member).filter(
        Member.id == renewal_data.member_id
    ).first()

    if not member:
        raise HTTPException(
            status_code=404,
            detail="Member not found"
        )

    latest_membership = (
        db.query(Membership)
        .filter(Membership.member_id == renewal_data.member_id)
        .order_by(Membership.due_date.desc())
        .first()
    )

    if not latest_membership:
        raise HTTPException(
            status_code=404,
            detail="No previous membership found for this member"
        )

    if renewal_data.start_date <= latest_membership.due_date:
        raise HTTPException(
            status_code=409,
            detail="Renewal start date must be later than the latest membership due date"
        )

    due_date = calculate_due_date(renewal_data.start_date)

    new_membership = Membership(
        member_id=renewal_data.member_id,
        start_date=renewal_data.start_date,
        due_date=due_date
    )

    try:
        db.add(new_membership)
        db.commit()
        db.refresh(new_membership)

    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to renew membership. Please try again."
        )

    return {
        "message": "Membership renewed successfully",
        "membership": {
            "id": new_membership.id,
            "member_id": new_membership.member_id,
            "start_date": new_membership.start_date,
            "due_date": new_membership.due_date
        }
    }


@router.delete("/{membership_id}")
def delete_membership(
    membership_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    membership = db.query(Membership).filter(
        Membership.id == membership_id
    ).first()

    if not membership:
        raise HTTPException(
            status_code=404,
            detail="Membership not found"
        )

    deleted_membership_id = membership.id
    deleted_member_id = membership.member_id

    try:
        db.delete(membership)
        db.commit()

    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to delete membership. Please try again."
        )

    return {
        "message": "Membership deleted successfully",
        "membership_id": deleted_membership_id,
        "member_id": deleted_member_id
    }
