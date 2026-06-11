"""
사진 업로드 API 라우터
- 멀티파트 폼 데이터로 사진 수신
- EXIF 추출 → 썸네일 생성 → 얼굴 인식 파이프라인
- 외장하드/버퍼 자동 분기 저장
"""

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from pathlib import Path

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


def _create_video_thumbnail(video_bytes: bytes, file_hash: str) -> str | None:
    """
    동영상 첫 프레임을 추출하여 JPEG 썸네일 생성 (OpenCV 사용)
    Returns: 썸네일 파일 경로 (str) 또는 None
    """
    import cv2
    import numpy as np
    import tempfile
    import shutil
    from config import settings

    thumb_dir = settings.thumbnail_dir
    thumb_path = thumb_dir / f"{file_hash}_thumb.jpg"

    # 이미 존재하면 재생성 불필요
    if thumb_path.exists():
        return str(thumb_path)

    # 동영상 바이트를 임시 파일로 저장 (OpenCV는 파일 경로 필요)
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp.write(video_bytes)
        tmp_path = tmp.name

    try:
        cap = cv2.VideoCapture(tmp_path)
        if not cap.isOpened():
            print(f"⚠️ 동영상 열기 실패: {file_hash}")
            return None

        # 첫 프레임 읽기
        ret, frame = cap.read()
        cap.release()

        if not ret or frame is None:
            return None

        # 썸네일 크기로 리사이즈 (320x320 내에 맞춤)
        h, w = frame.shape[:2]
        target_size = settings.THUMBNAIL_WIDTH
        if w > h:
            new_w = target_size
            new_h = int(h * target_size / w)
        else:
            new_h = target_size
            new_w = int(w * target_size / h)

        thumb_frame = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_AREA)

        # JPEG로 저장 (한글 경로 문제 우회: 임시 파일 → 이동)
        thumb_dir.mkdir(parents=True, exist_ok=True)
        tmp_thumb = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
        tmp_thumb_path = tmp_thumb.name
        tmp_thumb.close()
        cv2.imwrite(tmp_thumb_path, thumb_frame, [cv2.IMWRITE_JPEG_QUALITY, settings.THUMBNAIL_QUALITY])
        shutil.move(tmp_thumb_path, str(thumb_path))

        print(f"🎬 동영상 썸네일 생성: {thumb_path.name}")
        return str(thumb_path)

    except Exception as e:
        print(f"⚠️ 동영상 썸네일 생성 오류: {e}")
        return None
    finally:
        import os
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


@router.post("/upload", response_model=PhotoUploadResponse)
async def upload_photo(
    file: UploadFile = File(...),
    latitude: float | None = Form(None),
    longitude: float | None = Form(None),
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
    allowed_types = {
        "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp",
        "video/mp4", "video/quicktime", "video/3gpp", "video/x-msvideo",
        "video/webm", "video/mpeg", "application/octet-stream",
    }
    if file.content_type not in allowed_types:
        raise HTTPException(status_code=400, detail=f"지원하지 않는 파일 형식: {file.content_type}")

    # 파일 크기 제한 (500MB)
    contents = await file.read()
    if len(contents) > 500 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="파일 크기가 500MB를 초과합니다")

    # 1. 파일 해시 생성 (고유 ID)
    file_hash = thumbnail_service.generate_file_hash(contents)

    # 중복 확인
    existing = await db.fetch_one("SELECT id FROM photos WHERE id = ?", (file_hash,))
    if existing:
        raise HTTPException(status_code=409, detail="이미 업로드된 사진입니다")

    # 2. EXIF 메타데이터 추출 (동영상은 파일명에서 날짜 추출)
    exif_data = exif_service.extract_exif(contents, filename=file.filename)

    # GPS: EXIF 우선, 없으면 앱이 보낸 위치 사용
    place_name = None
    final_lat = exif_data["latitude"]
    final_lon = exif_data["longitude"]
    has_gps = exif_data["has_gps"]

    # 디버깅 로그
    print(f"🔍 GPS 디버그: EXIF has_gps={has_gps}, lat={final_lat}, lon={final_lon}")
    print(f"🔍 GPS 디버그: 앱 전송 lat={latitude}, lon={longitude}")

    # EXIF에 GPS 없으면 앱에서 보낸 위치로 보완
    if not has_gps and latitude is not None and longitude is not None:
        final_lat = latitude
        final_lon = longitude
        has_gps = True
        print(f"📍 앱 위치 사용: {latitude:.6f}, {longitude:.6f}")

    address_key = None
    if has_gps:
        place_name, address_key = await exif_service.reverse_geocode(final_lat, final_lon)
    
    # exif_data 업데이트
    exif_data["latitude"] = final_lat
    exif_data["longitude"] = final_lon
    exif_data["has_gps"] = has_gps

    # 3. 썸네일 생성 (이미지: Pillow / 동영상: OpenCV 첫 프레임)
    is_video = file.content_type and file.content_type.startswith("video/")
    thumb_path = None
    thumb_bytes = None
    preview_path = None
    if is_video:
        try:
            thumb_path = _create_video_thumbnail(contents, file_hash)
        except Exception as e:
            print(f"⚠️ 동영상 썸네일 생성 실패: {e}")
        # 동영상 미리보기 생성 (360p MP4)
        try:
            from services.preview_service import preview_service
            preview_path = preview_service.create_preview(contents, file_hash)
        except Exception as e:
            print(f"⚠️ 동영상 미리보기 생성 실패: {e}")
    else:
        try:
            thumb_path, thumb_bytes = thumbnail_service.create_thumbnail(contents, file_hash)
        except Exception as e:
            print(f"⚠️ 썸네일 생성 실패: {e}")

    # 4. 얼굴 인식 (이미지만)
    detected_faces = []
    if not is_video:
        detected_faces = await face_service.tag_photo_faces(file_hash, contents)

    # 5. 저장소 분기
    storage_status = "buffer"
    
    # 같은 건물(번지+도로)의 기존 폴더가 있으면 해당 폴더 사용 (스타필드 Nike→스타필드 하남 병합)
    existing_folder = storage_service.find_existing_folder_by_address(
        exif_data["taken_at"], address_key
    )
    if existing_folder:
        target_folder = existing_folder
    else:
        target_folder = storage_service.get_target_folder(exif_data["taken_at"], place_name)
    target_folder_name = target_folder.relative_to(storage_service.external_path).as_posix()

    if storage_service.is_drive_connected():
        # 외장하드 직접 저장 (target_folder 이미 계산됨)
        # 임시로 버퍼에 저장
        temp_buffer = buffer_service.save_to_buffer(contents, file.filename)
        saved_path = storage_service.save_to_external(
            temp_buffer,
            target_folder,
            file.filename
        )
        if saved_path:
            storage_status = "external_drive"
            # 건물 주소 키 캐시 저장 (같은 건물 사진 병합용)
            storage_service.save_address_key(target_folder, address_key)
            # 버퍼 파일 삭제 (외장하드에 저장 완료)
            try:
                from pathlib import Path as P
                buf_file = P(temp_buffer)
                if buf_file.exists():
                    buf_file.unlink()
            except Exception:
                pass
    else:
        # 버퍼에 임시 저장
        buffer_path = buffer_service.save_to_buffer(contents, file.filename)
        storage_status = "buffer"

    # 6. DB에 메타데이터 저장 (photos 먼저 → buffer_queue는 FK 참조)
    buffer_file_path = buffer_path if storage_status == "buffer" else None
    await db.execute(
        """INSERT INTO photos
           (id, filename, taken_at, latitude, longitude, place_name,
            is_backed_up, thumbnail_path, buffer_path, file_size, camera_model, preview_path, uploaded_by)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            file_hash,
            file.filename,
            exif_data["taken_at"],
            exif_data["latitude"],
            exif_data["longitude"],
            place_name,
            1 if storage_status == "external_drive" else 0,
            thumb_path,
            buffer_file_path,
            len(contents),
            exif_data["camera_model"],
            preview_path,
            1,  # 가정용: 기본 사용자 ID
        )
    )

    # 7. 외장하드 미연결 시 버퍼 큐에 추가 (photos INSERT 이후)
    if storage_status == "buffer":
        await buffer_service.add_to_queue(file_hash, buffer_path, target_folder_name)

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
    request: Request,
):
    """즐겨찾기(하트) 토글 — 앱에서 보내는 형식 호환"""
    body = await request.json()

    # 앱이 보내는 형식: {"changes": [{"photo_id": "abc", "is_favorite": true}, ...]}
    changes = body.get("changes", [])
    if changes:
        updated = 0
        for change in changes:
            photo_id = change.get("photo_id")
            is_favorite = change.get("is_favorite", False)
            if photo_id:
                await db.execute(
                    "UPDATE photos SET is_favorite = ? WHERE id = ?",
                    (int(is_favorite), photo_id)
                )
                updated += 1
        return {"updated": updated}

    # 기존 형식 호환: {"photo_ids": ["abc"], "is_favorite": true}
    photo_ids = body.get("photo_ids", [])
    is_favorite = body.get("is_favorite", False)
    updated = 0
    for photo_id in photo_ids:
        await db.execute(
            "UPDATE photos SET is_favorite = ? WHERE id = ?",
            (int(is_favorite), photo_id)
        )
        updated += 1
    return {"updated": updated, "is_favorite": is_favorite}


@router.get("/", response_model=list[PhotoMetadata])
async def list_photos(
    page: int = 1,
    limit: int = 50,
    backed_up: bool | None = None,
    favorite: bool | None = None,
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
async def photos_by_place(place_id: int):
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
async def photos_by_person(person_id: int):
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
async def get_thumbnail(photo_id: str):
    """썸네일 이미지 반환"""
    photo = await db.fetch_one("SELECT thumbnail_path FROM photos WHERE id = ?", (photo_id,))
    if not photo or not photo["thumbnail_path"]:
        raise HTTPException(status_code=404, detail="썸네일을 찾을 수 없습니다")

    thumb_path = Path(photo["thumbnail_path"])
    if not thumb_path.exists():
        raise HTTPException(status_code=404, detail="썸네일 파일이 존재하지 않습니다")

    return FileResponse(str(thumb_path), media_type="image/jpeg")


@router.get("/preview/{photo_id}")
async def get_preview(photo_id: str):
    """동영상 미리보기(360p MP4) 서빙 — 앱 로컬 저장용"""
    photo = await db.fetch_one(
        "SELECT preview_path FROM photos WHERE id = ?", (photo_id,)
    )
    if not photo or not photo["preview_path"]:
        raise HTTPException(status_code=404, detail="미리보기가 없습니다")

    preview_path = Path(photo["preview_path"])
    if not preview_path.exists():
        raise HTTPException(status_code=404, detail="미리보기 파일을 찾을 수 없습니다")

    return FileResponse(
        str(preview_path),
        media_type="video/mp4",
        headers={"Accept-Ranges": "bytes"},
    )

@router.get("/file/{photo_id}")
async def get_original_file(photo_id: str, request: Request = None):
    """원본 파일 서빙 (사진/동영상) - Range 요청 지원"""
    from starlette.responses import StreamingResponse
    import os

    def _get_media_type(fp: Path) -> str:
        ext = fp.suffix.lower()
        media_types = {
            ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
            ".png": "image/png", ".webp": "image/webp",
            ".heic": "image/heic", ".heif": "image/heif",
            ".mp4": "video/mp4", ".mov": "video/quicktime",
            ".3gp": "video/3gpp", ".avi": "video/x-msvideo",
            ".webm": "video/webm",
        }
        return media_types.get(ext, "application/octet-stream")

    # 파일 경로 탐색
    file_path = None

    # 1) buffer_queue에서 조회
    record = await db.fetch_one(
        "SELECT buffer_file_path FROM buffer_queue WHERE photo_id = ?", (photo_id,)
    )
    if record and record["buffer_file_path"]:
        fp = Path(record["buffer_file_path"])
        if fp.exists():
            file_path = fp

    # 2) photos 테이블에서 조회 (buffer_path → original_path → preview_path → thumbnail_path 순)
    if not file_path:
        photo = await db.fetch_one(
            "SELECT buffer_path, original_path, preview_path, thumbnail_path FROM photos WHERE id = ?", (photo_id,)
        )
        if photo:
            if photo["buffer_path"]:
                bp = Path(photo["buffer_path"])
                if bp.exists():
                    file_path = bp
            if not file_path and photo["original_path"]:
                op = Path(photo["original_path"])
                if op.exists():
                    file_path = op
            if not file_path and photo["preview_path"]:
                pp = Path(photo["preview_path"])
                if pp.exists():
                    file_path = pp
            if not file_path and photo["thumbnail_path"]:
                tp = Path(photo["thumbnail_path"])
                if tp.exists():
                    file_path = tp

    if not file_path:
        raise HTTPException(status_code=404, detail="파일을 찾을 수 없습니다")

    media_type = _get_media_type(file_path)
    file_size = os.path.getsize(file_path)

    # Range 요청 처리 (동영상 스트리밍용)
    range_header = request.headers.get("range") if request else None

    if range_header and range_header.startswith("bytes="):
        # Range: bytes=0-999 형식 파싱
        range_spec = range_header.replace("bytes=", "")
        parts = range_spec.split("-")
        start = int(parts[0]) if parts[0] else 0
        end = int(parts[1]) if parts[1] else file_size - 1
        end = min(end, file_size - 1)
        content_length = end - start + 1

        def iter_file():
            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = content_length
                while remaining > 0:
                    chunk_size = min(8192, remaining)
                    data = f.read(chunk_size)
                    if not data:
                        break
                    remaining -= len(data)
                    yield data

        return StreamingResponse(
            iter_file(),
            status_code=206,
            media_type=media_type,
            headers={
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Accept-Ranges": "bytes",
                "Content-Length": str(content_length),
            }
        )
    else:
        # Range 없는 일반 요청
        return FileResponse(
            str(file_path),
            media_type=media_type,
            headers={"Accept-Ranges": "bytes"}
        )


@router.delete("/delete")
async def delete_photos(request: Request):
    """
    사진 삭제 (서버에서 완전 삭제)

    - DB 레코드 삭제 (photos, photo_persons, photo_places, buffer_queue)
    - 썸네일 파일 삭제
    - 버퍼 파일 삭제
    - 외장하드에 이미 이관된 파일은 그대로 유지
    """
    import os

    body = await request.json()
    photo_ids = body.get("photo_ids", [])

    if not photo_ids:
        raise HTTPException(status_code=400, detail="삭제할 사진 ID가 없습니다")

    deleted_count = 0

    for photo_id in photo_ids:
        # 사진 정보 조회
        photo = await db.fetch_one(
            "SELECT id, thumbnail_path, buffer_path FROM photos WHERE id = ?",
            (photo_id,)
        )
        if not photo:
            continue

        # 1. 썸네일 파일 삭제
        if photo["thumbnail_path"]:
            try:
                thumb = Path(photo["thumbnail_path"])
                if thumb.exists():
                    thumb.unlink()
                    print(f"🗑️ 썸네일 삭제: {thumb.name}")
            except Exception as e:
                print(f"⚠️ 썸네일 삭제 실패: {e}")

        # 2. 버퍼 파일 삭제
        if photo["buffer_path"]:
            try:
                buf = Path(photo["buffer_path"])
                if buf.exists():
                    buf.unlink()
                    print(f"🗑️ 버퍼 파일 삭제: {buf.name}")
            except Exception as e:
                print(f"⚠️ 버퍼 파일 삭제 실패: {e}")

        # 3. buffer_queue에서 버퍼 파일 경로 확인 후 삭제
        buf_record = await db.fetch_one(
            "SELECT buffer_file_path FROM buffer_queue WHERE photo_id = ?",
            (photo_id,)
        )
        if buf_record and buf_record["buffer_file_path"]:
            try:
                buf_file = Path(buf_record["buffer_file_path"])
                if buf_file.exists():
                    buf_file.unlink()
            except Exception:
                pass

        # 4. DB 레코드 삭제 (관련 테이블 먼저)
        await db.execute("DELETE FROM photo_persons WHERE photo_id = ?", (photo_id,))
        await db.execute("DELETE FROM photo_places WHERE photo_id = ?", (photo_id,))
        await db.execute("DELETE FROM buffer_queue WHERE photo_id = ?", (photo_id,))
        await db.execute("DELETE FROM photos WHERE id = ?", (photo_id,))

        deleted_count += 1
        print(f"🗑️ 사진 삭제 완료: {photo_id[:16]}...")

    return {"deleted": deleted_count, "total_requested": len(photo_ids)}


@router.get("/map-data")
async def get_map_data():
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
