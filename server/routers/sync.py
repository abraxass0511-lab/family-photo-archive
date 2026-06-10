"""
동기화 API 라우터
- 앱 ↔ 서버 데이터 동기화
- 장소 검색 (Nominatim)
- 인물 관리
- 시스템 상태 확인
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File

from services.auth_service import get_current_user, require_admin
from services.exif_service import exif_service
from services.face_service import face_service
from services.storage_service import storage_service
from services.buffer_service import buffer_service
from services.thumbnail_service import thumbnail_service
from db.database import db
from models.schemas import (
    SyncResponse, PhotoMetadata, PersonCreate, PersonResponse,
    PlaceResponse, PlaceSearchResult, SystemStatus,
)

router = APIRouter(prefix="/api", tags=["동기화 & 시스템"])


# === 동기화 ===

@router.get("/sync", response_model=SyncResponse)
async def sync_data(
    last_sync_at: str | None = None,
):
    """
    전체 데이터 동기화 (앱 → 서버)

    - last_sync_at 이후 변경된 데이터만 반환
    - 앱은 이 데이터로 로컬 DB를 업데이트
    """
    from datetime import datetime, timezone
    from pathlib import Path

    # 파일이 삭제된 레코드 자동 정리
    all_photos_check = await db.fetch_all("SELECT id, buffer_path, original_path FROM photos")
    for p in all_photos_check:
        buffer_exists = Path(p["buffer_path"]).exists() if p["buffer_path"] else False
        original_exists = Path(p["original_path"]).exists() if p["original_path"] else False
        if not buffer_exists and not original_exists:
            await db.execute("DELETE FROM photo_persons WHERE photo_id = ?", (p["id"],))
            await db.execute("DELETE FROM photo_places WHERE photo_id = ?", (p["id"],))
            await db.execute("DELETE FROM buffer_queue WHERE photo_id = ?", (p["id"],))
            await db.execute("DELETE FROM photos WHERE id = ?", (p["id"],))
            print(f"🧹 파일 없는 레코드 정리: {p['id'][:16]}...")

    # 사진 메타데이터
    if last_sync_at:
        photos = await db.fetch_all(
            "SELECT * FROM photos WHERE created_at > ? ORDER BY taken_at DESC",
            (last_sync_at,)
        )
    else:
        photos = await db.fetch_all("SELECT * FROM photos ORDER BY taken_at DESC")

    photo_list = []
    for p in photos:
        persons = await db.fetch_all(
            """SELECT pe.name FROM photo_persons pp
               JOIN persons pe ON pp.person_id = pe.id
               WHERE pp.photo_id = ?""",
            (p["id"],)
        )
        photo_list.append(PhotoMetadata(
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

    # 인물 목록
    persons_data = await db.fetch_all("SELECT * FROM persons ORDER BY name")
    person_list = [
        PersonResponse(
            id=p["id"],
            name=p["name"],
            photo_count=p["photo_count"],
            sample_thumbnail=p["sample_thumbnail"],
        )
        for p in persons_data
    ]

    # 장소 목록
    places_data = await db.fetch_all(
        """SELECT pl.*, COUNT(pp.photo_id) as photo_count
           FROM places pl
           LEFT JOIN photo_places pp ON pl.id = pp.place_id
           GROUP BY pl.id
           ORDER BY pl.name"""
    )
    place_list = [
        PlaceResponse(
            id=p["id"],
            name=p["name"],
            address=p["address"],
            latitude=p["latitude"],
            longitude=p["longitude"],
            category=p["category"],
            photo_count=p["photo_count"],
        )
        for p in places_data
    ]

    return SyncResponse(
        photos=photo_list,
        persons=person_list,
        places=place_list,
        server_time=datetime.now(timezone.utc).isoformat(),
    )


# === 장소 검색 (카카오 로컬 + Nominatim 융합, 100% 무료) ===

@router.get("/places/search", response_model=list[PlaceSearchResult])
async def search_places(
    q: str,
    limit: int = 5,
):
    """
    장소 검색 (카카오 로컬 API 우선 → Nominatim 보조)

    - 카카오: 한국 상호명 최적화 (일 10만 건 무료)
    - Nominatim: 카카오 미설정 또는 실패 시 폴백
    """
    if not q or len(q) < 2:
        raise HTTPException(status_code=400, detail="검색어는 2자 이상이어야 합니다")

    from services.kakao_service import kakao_service

    results = []

    # 1차: 카카오 로컬 API (한국 상호명에 강함)
    if kakao_service.is_available:
        kakao_results = await kakao_service.search_places(q, limit=limit)
        results.extend(kakao_results)

    # 2차: Nominatim 보조 (카카오 결과 부족 시)
    if len(results) < limit:
        remaining = limit - len(results)
        nominatim_results = await exif_service.search_places(q, limit=remaining)
        # 중복 제거 (좌표가 0.001도 이내이면 동일 장소로 판단)
        for nr in nominatim_results:
            nr["source"] = "nominatim"
            is_duplicate = False
            for existing in results:
                if (abs(existing.get("latitude", 0) - nr.get("latitude", 0)) < 0.001 and
                    abs(existing.get("longitude", 0) - nr.get("longitude", 0)) < 0.001):
                    is_duplicate = True
                    break
            if not is_duplicate:
                results.append(nr)

    return [PlaceSearchResult(**r) for r in results[:limit]]


@router.get("/places/search/usage")
async def place_search_usage():
    """카카오 API 일일 사용량 확인"""
    from services.kakao_service import kakao_service
    return await kakao_service.get_daily_usage()


# === 인물 관리 ===

@router.post("/persons", response_model=PersonResponse)
async def create_person(
    data: PersonCreate,
):
    """인물 등록"""
    cursor = await db.execute(
        "INSERT INTO persons (name) VALUES (?)",
        (data.name,)
    )
    return PersonResponse(id=cursor.lastrowid, name=data.name, photo_count=0)


@router.get("/persons", response_model=list[PersonResponse])
async def list_persons():
    """인물 목록"""
    persons = await db.fetch_all("SELECT * FROM persons ORDER BY name")
    return [
        PersonResponse(
            id=p["id"],
            name=p["name"],
            photo_count=p["photo_count"],
            sample_thumbnail=p["sample_thumbnail"],
        )
        for p in persons
    ]


@router.post("/persons/{person_id}/face")
async def register_face(
    person_id: int,
    file: UploadFile = File(...),
):
    """인물 얼굴 등록 (기준 사진 업로드)"""
    person = await db.fetch_one("SELECT id FROM persons WHERE id = ?", (person_id,))
    if not person:
        raise HTTPException(status_code=404, detail="인물을 찾을 수 없습니다")

    contents = await file.read()
    success = await face_service.register_face(person_id, contents)

    if success:
        return {"message": f"인물 {person_id}의 얼굴 등록 완료"}
    else:
        raise HTTPException(status_code=400, detail="얼굴을 인식할 수 없습니다. 다른 사진을 시도하세요.")


@router.delete("/persons/{person_id}")
async def delete_person(person_id: int, admin: dict = Depends(require_admin)):
    """인물 삭제 (관리자 전용)"""
    await db.execute("DELETE FROM photo_persons WHERE person_id = ?", (person_id,))
    await db.execute("DELETE FROM persons WHERE id = ?", (person_id,))
    return {"message": f"인물 {person_id} 삭제 완료"}


# === 시스템 상태 ===

@router.get("/status", response_model=SystemStatus)
async def system_status():
    """시스템 상태 확인"""
    total_photos = await db.fetch_one("SELECT COUNT(*) as cnt FROM photos")
    total_persons = await db.fetch_one("SELECT COUNT(*) as cnt FROM persons")
    pending = await buffer_service.get_pending_count()

    # DB 파일 크기
    from config import settings
    from pathlib import Path
    db_path = Path(settings.DATA_DIR) / "photo_archive.db"
    db_size = db_path.stat().st_size / (1024 * 1024) if db_path.exists() else 0

    return SystemStatus(
        server_running=True,
        external_drive_connected=storage_service.is_drive_connected(),
        external_drive_path=settings.EXTERNAL_DRIVE_PATH,
        buffer_pending_count=pending,
        total_photos=total_photos["cnt"] if total_photos else 0,
        total_persons=total_persons["cnt"] if total_persons else 0,
        db_size_mb=round(db_size, 2),
        thumbnail_size_mb=thumbnail_service.get_total_size_mb(),
    )


@router.post("/buffer/process")
async def process_buffer(admin: dict = Depends(require_admin)):
    """버퍼 → 외장하드 수동 이관 트리거 (관리자 전용)"""
    result = await buffer_service.process_pending_queue()
    return result


# === 정적 웹 배포 ===

@router.post("/deploy")
async def deploy_web(
    password: str,
    admin: dict = Depends(require_admin),
):
    """
    정적 웹사이트 빌드 + 배포 (관리자 전용)

    - AES-256-GCM으로 사진 데이터 암호화
    - Cloudflare Pages / GitHub Pages로 자동 배포
    """
    if not password or len(password) < 4:
        raise HTTPException(status_code=400, detail="비밀번호는 4자 이상이어야 합니다")

    from services.deploy_service import deploy_service
    result = await deploy_service.build_and_deploy(password)
    return result

