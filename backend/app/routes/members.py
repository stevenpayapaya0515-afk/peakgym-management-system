from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.members import Member
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.members import MemberCreate, MemberUpdate
import calendar
from datetime import date
import io
import uuid
from pathlib import Path

from fastapi import UploadFile, File
from PIL import Image, ImageOps, UnidentifiedImageError

from app.models.memberships import Membership
from fastapi.responses import FileResponse

router = APIRouter(prefix="/members", tags=["Member Management"])

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
def get_members(
    search: str | None = None,
    status: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    allowed_statuses = [
        "Active",
        "Expired",
        "Upcoming",
        "No Membership"
    ]

    if status and status not in allowed_statuses:
        raise HTTPException(
            status_code=422,
            detail="Invalid membership status"
        )

    query = db.query(Member)

    if search:
        query = query.filter(
            Member.full_name.ilike(f"%{search.strip()}%")
        )

    members = query.order_by(Member.id.desc()).all()

    today = date.today()
    results = []

    for member in members:

        memberships = (
            db.query(Membership)
            .filter(Membership.member_id == member.id)
            .order_by(Membership.due_date.desc())
            .all()
        )

        selected_membership = None
        member_status = "No Membership"

        active = [
            m for m in memberships
            if m.start_date <= today <= m.due_date
        ]

        upcoming = [
            m for m in memberships
            if m.start_date > today
        ]

        if active:
            selected_membership = active[0]
            member_status = "Active"

        elif upcoming:
            selected_membership = min(
                upcoming,
                key=lambda m: m.start_date
            )
            member_status = "Upcoming"

        elif memberships:
            selected_membership = memberships[0]
            member_status = "Expired"

        if status and member_status != status:
            continue

        results.append({
            "id": member.id,
            "full_name": member.full_name,
            "photo": member.photo,
            "membership_id": (
                selected_membership.id
                if selected_membership else None
            ),
            "start_date": (
                selected_membership.start_date
                if selected_membership else None
            ),
            "due_date": (
                selected_membership.due_date
                if selected_membership else None
            ),
            "status": member_status,
            "created_at": member.created_at
        })

    return results


@router.post("/{member_id}/photo")
def upload_member_photo(
    member_id: int,
    file: UploadFile = File(...),
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

    # Read uploaded file and enforce 2 MB limit
    image_data = file.file.read(2 * 1024 * 1024 + 1)

    if len(image_data) > 2 * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail="Image must not exceed 2 MB"
        )

    if not image_data:
        raise HTTPException(
            status_code=400,
            detail="Uploaded image is empty"
        )

    # Validate and re-encode image
    try:
        with Image.open(io.BytesIO(image_data)) as image:
            if image.format not in ["JPEG", "PNG"]:
                raise HTTPException(
                    status_code=400,
                    detail="Only JPEG and PNG images are allowed"
                )

            image.verify()

        with Image.open(io.BytesIO(image_data)) as image:
            width, height = image.size

            if width > 5000 or height > 5000:
                raise HTTPException(
                    status_code=422,
                    detail="Image dimensions must not exceed 5000 pixels per side"
                )

            if width * height > 12_000_000:
                raise HTTPException(
                    status_code=422,
                    detail="Image must not exceed 12 megapixels"
                )

            image = ImageOps.exif_transpose(image)
            image.load()

            image_format = image.format

            if image_format == "JPEG":
                image = image.convert("RGB")
                extension = ".jpg"
            else:
                if image.mode not in ["RGB", "RGBA"]:
                    image = image.convert(
                        "RGBA" if "transparency" in image.info else "RGB"
                    )
                extension = ".png"

            # Private storage directory
            storage_dir = (
                Path(__file__).resolve().parents[2]
                / "storage"
                / "member_photos"
            )

            storage_dir.mkdir(parents=True, exist_ok=True)

            filename = uuid.uuid4().hex + extension
            image_path = storage_dir / filename

            image.save(
                image_path,
                format=image_format,
                optimize=True
            )

    except HTTPException:
        raise

    except (UnidentifiedImageError, OSError, Image.DecompressionBombError):
        raise HTTPException(
            status_code=400,
            detail="Invalid or corrupted image file"
        )

    # Save filename in database
    old_photo = member.photo

    try:
        member.photo = filename
        db.commit()
        db.refresh(member)

    except Exception:
        db.rollback()

        if image_path.exists():
            image_path.unlink()

        raise

    # Remove previous photo after successful database update
    if old_photo and Path(old_photo).name == old_photo:
        old_path = storage_dir / old_photo

        if old_path.is_file():
            old_path.unlink()

    return {
        "message": "Member photo uploaded successfully",
        "member": {
            "id": member.id,
            "full_name": member.full_name,
            "photo": member.photo
        }
    }


@router.get("/{member_id}/photo")
def get_member_photo(
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

    if not member.photo:
        raise HTTPException(
            status_code=404,
            detail="Member has no uploaded photo"
        )

    # Only allow safe filenames
    if Path(member.photo).name != member.photo:
        raise HTTPException(
            status_code=400,
            detail="Invalid photo filename"
        )

    storage_dir = (
        Path(__file__).resolve().parents[2]
        / "storage"
        / "member_photos"
    )

    image_path = storage_dir / member.photo

    if not image_path.is_file():
        raise HTTPException(
            status_code=404,
            detail="Member photo file not found"
        )

    extension = image_path.suffix.lower()

    if extension not in [".jpg", ".png"]:
        raise HTTPException(
            status_code=400,
            detail="Invalid photo format"
        )

    media_type = (
        "image/jpeg" if extension == ".jpg"
        else "image/png"
    )

    return FileResponse(
        path=image_path,
        media_type=media_type,
        filename=image_path.name,
        content_disposition_type="inline"
    )


@router.delete("/{member_id}/photo")
def delete_member_photo(
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

    if not member.photo:
        raise HTTPException(
            status_code=404,
            detail="Member has no uploaded photo"
        )

    if Path(member.photo).name != member.photo:
        raise HTTPException(
            status_code=400,
            detail="Invalid photo filename"
        )

    storage_dir = (
        Path(__file__).resolve().parents[2]
        / "storage"
        / "member_photos"
    )

    image_path = storage_dir / member.photo

    old_photo = member.photo

    # Clear photo reference in database
    member.photo = None

    try:
        db.commit()
        db.refresh(member)
    except Exception:
        db.rollback()
        raise

    # Delete physical image after successful database update
    if image_path.is_file():
        image_path.unlink()

    return {
        "message": "Member photo deleted successfully",
        "member": {
            "id": member.id,
            "full_name": member.full_name,
            "photo": member.photo
        },
        "deleted_photo": old_photo
    }


@router.get("/{member_id}")
def get_member_details(
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
    membership_history = []

    for membership in memberships:
        if membership.start_date > today:
            status = "Upcoming"
        elif membership.due_date >= today:
            status = "Active"
        else:
            status = "Expired"

        membership_history.append({
            "id": membership.id,
            "start_date": membership.start_date,
            "due_date": membership.due_date,
            "status": status,
            "created_at": membership.created_at
        })

    return {
        "id": member.id,
        "full_name": member.full_name,
        "photo": member.photo,
        "created_at": member.created_at,
        "total_memberships": len(membership_history),
        "memberships": membership_history
    }


@router.post("/")
def create_member(
    member_data: MemberCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )

    if not date(1900, 1, 1) <= member_data.start_date <= date(2099, 12, 31):
        raise HTTPException(
            status_code=422,
            detail="Start date must be between 1900-01-01 and 2099-12-31"
        )

    due_date = calculate_due_date(member_data.start_date)

    try:
        member = Member(
            full_name=member_data.full_name.strip()
        )

        db.add(member)
        db.flush()

        membership = Membership(
            member_id=member.id,
            start_date=member_data.start_date,
            due_date=due_date
        )

        db.add(membership)
        db.commit()

        db.refresh(member)
        db.refresh(membership)

    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to register member. Please try again."
        )

    return {
        "message": "Member registered successfully",
        "member": {
            "id": member.id,
            "full_name": member.full_name,
            "photo": member.photo,
            "created_at": member.created_at
        },
        "membership": {
            "id": membership.id,
            "start_date": membership.start_date,
            "due_date": membership.due_date
        }
    }


@router.put("/{member_id}")
def update_member(
    member_id: int,
    member_data: MemberUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(
            status_code=403,
            detail="Access denied"
        )
    
    member = db.query(Member).filter(Member.id == member_id).first()

    if not member:
        raise HTTPException(
            status_code=404,
            detail="Member not found"
        )

    if member_data.full_name is not None:
        member.full_name = member_data.full_name

    db.commit()
    db.refresh(member)

    return {
        "message": "Member updated successfully",
        "member": {
            "id": member.id,
            "full_name": member.full_name,
            "photo": member.photo,
            "created_at": member.created_at
        }
    }
  
@router.delete("/{member_id}")
def delete_member(
    member_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role not in ["admin", "staff"]:
        raise HTTPException(status_code=403, detail="Access denied")

    member = db.query(Member).filter(Member.id == member_id).first()

    if not member:
        raise HTTPException(status_code=404, detail="Member not found")

    photo_filename = member.photo

    try:
        # Delete the member's membership history first
        db.query(Membership).filter(
            Membership.member_id == member_id
        ).delete(synchronize_session=False)

        # Delete the member
        db.delete(member)

        db.commit()

    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to delete member. Please try again."
        )

    # Remove the physical photo after successful database deletion
    if photo_filename and Path(photo_filename).name == photo_filename:
        storage_dir = (
            Path(__file__).resolve().parents[2]
            / "storage"
            / "member_photos"
        )

        photo_path = storage_dir / photo_filename

        try:
            if photo_path.is_file():
                photo_path.unlink()
        except OSError:
            pass

    return {"message": "Member deleted successfully"}