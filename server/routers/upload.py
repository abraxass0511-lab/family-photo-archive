"""
사진 업로드 API 라우터
- 멀티파트 폼 데이터로 사진 수신
- EXIF 추출 → 썸네일 생성 → 얼굴 인식 파이프라인
- 외장하드/버퍼 자동 분기 저장
"""

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from fastapi.responses import FileResponse

from services.auth_service import get_current_user
from services.exif_service import exif_service
from services.thumbnail_service import thumbnail_service
from services.face_service import face_service
from services.storage_service import storage_service
from services.buffer_service import buffer_service
from db.database import db
from models.schemas import (
    PhotoUploadResponse, PhotoLocationMatch,
    FavoriteToggle, PhotoMetadata,
)

router = APIRouter(prefix="/api/photos", tags=["사진 관리"])


@router.post("/upload", response_model=PhotoUploadResponse)
async def upload_photo(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """
    사진 업로드 (전체 파이프라인)

    1. 파일 수신
    2. SHA-256 해시 → 고유 ID 생성
    3. EXIF 메타데이터 추출 (날짜, GPS, 카메라)
    4. 썸네일 생성 (320x320, ~20KB)
    5. 얼굴 인식 → 자동 태깅
    6. 외장하드 연결 여부에 따라 저장소 분기
    """
    # 파일 타입 검증 (보안)
    allowed_types = {"image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"}
    if file.content_type not in allowed_types:
        raise HTTPException(status_code=400, detail=f"지원하지 않는 파일 형식: {file.content_type}")

    # 파일 크기 제한 (50MB)
    contents = await file.read()
    if len(contents) > 50 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="파일 크기가 50MB를 초과합니다")

    # 1. 파일 해시 생성 (고유 ID)
    file_hash = thumbnail_service.generate_file_hash(contents)

    # 중복 확인
    existing = await db.fetch_one("SELECT id FROM photos WHERE id = ?", (file_hash,))
    if existing:
        raise HTTPException(status_code=409, detail="이미 업로드된 사진입니다")

    # 2. EXIF 메타데이터 추출
    exif_data = exif_service.extract_exif(contents)

    # GPS 있으면 역지오코딩
    place_name = None
    if exif_data["has_gps"]:
        place_name = await exif_service.reverse_geocode(
            exif_data["latitude"], exif_data["longitude"]
        )

    # 3. 썸네일 생성
    thumb_path, thumb_bytes = thumbnail_service.create_thumbnail(contents, file_hash)

    # 4. 얼굴 인식
    detected_faces = await face_service.tag_photo_faces(file_hash, contents)

    # 5. 저장소 분기
    storage_status = "buffer"
    target_folder_name = storage_service.get_target_folder(
        exif_data["taken_at"], place_name
    ).name

    if storage_service.is_drive_connected():
        # 외장하드 직접 저장
        target_folder = storage_service.get_target_folder(exif_data["taken_at"], place_name)
        saved_path = storage_service.save_to_external(
            # 임시로 버퍼에 저장 후 이동
            buffer_service.save_to_buffer(contents, file.filename),
            target_folder,
            file.filename
        )
        if saved_path:
            storage_status = "external_drive"
    else:
        # 버퍼에 임시 저장
        buffer_path = buffer_service.save_to_buffer(contents, file.filename)
        await buffer_service.add_to_queue(file_hash, buffer_path, target_folder_name)
        storage_status = "buffer"

    # 6. DB에 메타데이터 저장
    await db.execute(
        """INSERT INTO photos
           (id, filename, taken_at, latitude, longitude, place_name,
            is_backed_up, thumbnail_path, file_size, camera_model, uploaded_by)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            file_hash,
            file.filename,
            exif_data["taken_at"],
            exif_data["latitude"],
            exif_data["longitude"],
            place_name,
            1 if storage_status == "external_drive" else 0,
            thumb_path,
            len(contents),
            exif_data["camera_model"],
            current_user["id"],
        )
    )

    return PhotoUploadResponse(
        photo_id=file_hash,
        filename=file.filename,
        thumbnail_path=thumb_path,
        storage_status=storage_status,
        extracted_metadata=exif_data,
        detected_faces=detected_faces,
    )


@router.post("/match-location")
async def match_photos_to_location(
    data: PhotoLocationMatch,
    current_user: dict = Depends(get_current_user),
):
    """
    사진-장소 수동 매칭 (핵심 기능)

    - 다중 선택한 사진들에 장소 정보를 일괄 매칭
    """
    # 장소 생성 또는 조회
    existing_place = await db.fetch_one(
        "SELECT id FROM places WHERE name = ? AND latitude = ? AND longitude = ?",
        (data.place_name, data.latitude, data.longitude)
    )

    if existing_place:
        place_id = existing_place["id"]
    else:
        cursor = await db.execute(
            """INSERT INTO places (name, address, latitude, longitude, category)
               VALUES (?, ?, ?, ?, ?)""",
            (data.place_name, data.address, data.latitude, data.longitude, data.category)
        )
        place_id = cursor.lastrowid

    # 선택한 사진들에 장소 매칭
    matched = 0
    for photo_id in data.photo_ids:
        # 사진 존재 확인
        photo = await db.fetch_one("SELECT id FROM photos WHERE id = ?", (photo_id,))
        if not photo:
            continue

        # photo_places 연결
        await db.execute(
            """INSERT OR REPLACE INTO photo_places (photo_id, place_id) VALUES (?, ?)""",
            (photo_id, place_id)
        )

        # photos 테이블도 업데이트
        await db.execute(
            """UPDATE photos SET latitude = ?, longitude = ?, place_name = ? WHERE id = ?""",
            (data.latitude, data.longitude, data.place_name, photo_id)
        )
        matched += 1

    return {
        "message": f"{matched}장의 사진에 장소 '{data.place_name}'이 매칭되었습니다",
        "place_id": place_id,
        "matched_count": matched,
    }


@router.post("/favorites")
async def toggle_favorites(
    data: FavoriteToggle,
    current_user: dict = Depends(get_current_user),
):
    """즐겨찾기(하트) 토글"""
    updated = 0
    for photo_id in data.photo_ids:
        await db.execute(
            "UPDATE photos SET is_favorite = ? WHERE id = ?",
            (int(data.is_favorite), photo_id)
        )
        updated += 1
    return {"updated": updated, "is_favorite": data.is_favorite}


@router.get("/", response_model=list[PhotoMetadata])
async def list_photos(
    page: int = 1,
    limit: int = 50,
    backed_up: bool | None = None,
    favorite: bool | None = None,
    current_user: dict = Depends(get_current_user),
):
    """사진 목록 조회 (페이지네이션)"""
    query = "SELECT * FROM photos WHERE 1=1"
    params = []

    if backed_up is not None:
        query += " AND is_backed_up = ?"
        params.append(int(backed_up))

    if favorite is not None:
        query += " AND is_favorite = ?"
        params.append(int(favorite))

    query += " ORDER BY taken_at DESC LIMIT ? OFFSET ?"
    params.extend([limit, (page - 1) * limit])

    photos = await db.fetch_all(query, tuple(params))

    results = []
    for p in photos:
        # 인물 태그 조회
        persons = await db.fetch_all(
            """SELECT pe.name FROM photo_persons pp
               JOIN persons pe ON pp.person_id = pe.id
               WHERE pp.photo_id = ?""",
            (p["id"],)
        )

        results.append(PhotoMetadata(
            id=p["id"],
            filename=p["filename"],
            taken_at=str(p["taken_at"]) if p["taken_at"] else None,
            latitude=p["latitude"],
            longitude=p["longitude"],
            place_name=p["place_name"],
            is_backed_up=bool(p["is_backed_up"]),
            is_favorite=bool(p["is_favorite"]),
            thumbnail_path=p["thumbnail_path"],
            persons=[per["name"] for per in persons],
            file_size=p["file_size"],
            camera_model=p["camera_model"],
        ))

    return results


@router.get("/by-place/{place_id}", response_model=list[PhotoMetadata])
async def photos_by_place(place_id: int, current_user: dict = Depends(get_current_user)):
    """특정 장소의 사진 목록"""
    photos = await db.fetch_all(
        """SELECT p.* FROM photos p
           JOIN photo_places pp ON p.id = pp.photo_id
           WHERE pp.place_id = ?
           ORDER BY p.taken_at DESC""",
        (place_id,)
    )

    return [
        PhotoMetadata(
            id=p["id"],
            filename=p["filename"],
            taken_at=str(p["taken_at"]) if p["taken_at"] else None,
            latitude=p["latitude"],
            longitude=p["longitude"],
            place_name=p["place_name"],
            is_backed_up=bool(p["is_backed_up"]),
            is_favorite=bool(p["is_favorite"]),
            thumbnail_path=p["thumbnail_path"],
            file_size=p["file_size"],
            camera_model=p["camera_model"],
        )
        for p in photos
    ]


@router.get("/by-person/{person_id}", response_model=list[PhotoMetadata])
async def photos_by_person(person_id: int, current_user: dict = Depends(get_current_user)):
    """특정 인물의 사진 목록"""
    photos = await db.fetch_all(
        """SELECT p.* FROM photos p
           JOIN photo_persons pp ON p.id = pp.photo_id
           WHERE pp.person_id = ?
           ORDER BY p.taken_at DESC""",
        (person_id,)
    )

    return [
        PhotoMetadata(
            id=p["id"],
            filename=p["filename"],
            taken_at=str(p["taken_at"]) if p["taken_at"] else None,
            latitude=p["latitude"],
            longitude=p["longitude"],
            place_name=p["place_name"],
            is_backed_up=bool(p["is_backed_up"]),
            is_favorite=bool(p["is_favorite"]),
            thumbnail_path=p["thumbnail_path"],
            file_size=p["file_size"],
            camera_model=p["camera_model"],
        )
        for p in photos
    ]


@router.get("/thumbnail/{photo_id}")
async def get_thumbnail(photo_id: str, current_user: dict = Depends(get_current_user)):
    """썸네일 이미지 반환"""
    photo = await db.fetch_one("SELECT thumbnail_path FROM photos WHERE id = ?", (photo_id,))
    if not photo or not photo["thumbnail_path"]:
        raise HTTPException(status_code=404, detail="썸네일을 찾을 수 없습니다")

    from pathlib import Path
    thumb_path = Path(photo["thumbnail_path"])
    if not thumb_path.exists():
        raise HTTPException(status_code=404, detail="썸네일 파일이 존재하지 않습니다")

    return FileResponse(str(thumb_path), media_type="image/jpeg")


@router.get("/map-data")
async def get_map_data(current_user: dict = Depends(get_current_user)):
    """지도 표시용 데이터 (좌표 + 사진 수)"""
    places = await db.fetch_all(
        """SELECT pl.*, COUNT(pp.photo_id) as photo_count
           FROM places pl
           LEFT JOIN photo_places pp ON pl.id = pp.place_id
           GROUP BY pl.id"""
    )

    return [
        {
            "place_id": p["id"],
            "name": p["name"],
            "latitude": p["latitude"],
            "longitude": p["longitude"],
            "category": p["category"],
            "photo_count": p["photo_count"],
        }
        for p in places
    ]
