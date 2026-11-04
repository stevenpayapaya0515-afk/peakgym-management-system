from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.user import UserCreate, UserUpdate
from app.security.password import hash_password

router = APIRouter(prefix="/users", tags=["User Management"])


@router.get("/")
def get_users(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Only administrators can view user accounts.
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    users = db.query(User).order_by(User.id.asc()).all()

    return [
        {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "role": user.role,
            "is_active": user.is_active
        }
        for user in users
    ]

@router.post("/")
def create_user(
    user_data: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Only administrators can create staff accounts.
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    # Check if username already exists.
    existing_user = db.query(User).filter(
        User.username == user_data.username
    ).first()

    if existing_user:
        raise HTTPException(
            status_code=409,
            detail="Username already exists"
        )

    # Create a new staff account.
    new_user = User(
        username=user_data.username,
        email=user_data.email,
        password=hash_password(user_data.password),
        role="staff",
        is_active=True,
        failed_attempts=0,
        locked_until=None
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "message": "Staff account created successfully",
        "user": {
            "id": new_user.id,
            "username": new_user.username,
            "email": new_user.email,
            "role": new_user.role,
            "is_active": new_user.is_active
        }
    }

@router.put("/{user_id}")
def update_user(
    user_id: int,
    user_data: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Only administrators can update user accounts.
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    # Prevent administrators from modifying their own account here.
    if current_user.id == user_id:
        raise HTTPException(
            status_code=403,
            detail="You cannot modify your own account through this endpoint"
        )

    target_user = db.query(User).filter(
        User.id == user_id
    ).first()

    if not target_user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    # Only staff accounts can be modified through this endpoint.
    if target_user.role != "staff":
        raise HTTPException(
            status_code=403,
            detail="Only staff accounts can be updated"
        )

    update_data = user_data.model_dump(exclude_unset=True)

    if not update_data:
        raise HTTPException(
            status_code=400,
            detail="No update information provided"
        )

    if "username" in update_data:
        existing_user = db.query(User).filter(
            User.username == update_data["username"],
            User.id != user_id
        ).first()

        if existing_user:
            raise HTTPException(
                status_code=409,
                detail="Username already exists"
            )

    for field, value in update_data.items():
        setattr(target_user, field, value)

    db.commit()
    db.refresh(target_user)

    return {
        "message": "Staff account updated successfully",
        "user": {
            "id": target_user.id,
            "username": target_user.username,
            "email": target_user.email,
            "role": target_user.role,
            "is_active": target_user.is_active
        }
    }

@router.patch("/{user_id}/status")
def update_user_status(
    user_id: int,
    is_active: bool,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Only administrators can change account status.
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    # Prevent administrators from changing their own status.
    if current_user.id == user_id:
        raise HTTPException(
            status_code=403,
            detail="You cannot change your own account status"
        )

    target_user = db.query(User).filter(
        User.id == user_id
    ).first()

    if not target_user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    # Only staff accounts can be managed here.
    if target_user.role != "staff":
        raise HTTPException(
            status_code=403,
            detail="Only staff account status can be changed"
        )

    target_user.is_active = is_active
    db.commit()
    db.refresh(target_user)

    status = "activated" if target_user.is_active else "deactivated"

    return {
        "message": f"Staff account {status} successfully",
        "user": {
            "id": target_user.id,
            "username": target_user.username,
            "email": target_user.email,
            "role": target_user.role,
            "is_active": target_user.is_active
        }
    }

@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Only administrators can delete staff accounts.
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Only administrators can delete staff accounts"
        )

    # Prevent administrators from deleting their own account.
    if current_user.id == user_id:
        raise HTTPException(
            status_code=400,
            detail="You cannot delete your own account"
        )

    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    # Only staff accounts can be deleted through this endpoint.
    if user.role != "staff":
        raise HTTPException(
            status_code=403,
            detail="Administrators cannot delete other administrator accounts"
        )

    db.delete(user)
    db.commit()

    return {
        "message": "Staff account deleted successfully",
        "user_id": user_id
    }