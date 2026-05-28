"""
Pydantic 데이터 모델 (API 요청/응답 스키마)
- 입력 검증 자동화 (SQL Injection 방어)
- 응답 직렬화
"""

from datetime import datetime
from pydantic import BaseModel, Field, field_validator
import re


# ============================================
# 사용자 관리 모델
# ============================================

class UserCreate(BaseModel):
    """사용자 등록 요청"""
    username: str = Field(..., min_length=3, max_length=30, description="로그인 ID")
    password: str = Field(..., min_length=8, max_length=128, description="비밀번호 (8자 이상)")
    display_name: str = Field(..., min_length=1, max_length=50, description="표시 이름")
    role: str = Field(default="member", description="역할 (admin/member)")

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        """사용자명: 영문/숫자/밑줄만 허용 (보안)"""
        if not re.match(r"^[a-zA-Z0-9_]+$", v):
            raise ValueError("사용자명은 영문, 숫자, 밑줄(_)만 사용 가능합니다")
        return v.lower()

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: str) -> str:
        if v not in ("admin", "member"):
            raise ValueError("역할은 'admin' 또는 'member'만 가능합니다")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        """비밀번호 강도 검증"""
        if len(v) < 8:
            raise ValueError("비밀번호는 최소 8자 이상이어야 합니다")
        if not re.search(r"[A-Za-z]", v):
            raise ValueError("비밀번호에 영문자가 포함되어야 합니다")
        if not re.search(r"[0-9]", v):
            raise ValueError("비밀번호에 숫자가 포함되어야 합니다")
        return v


class UserLogin(BaseModel):
    """로그인 요청"""
    username: str
    password: str


class UserResponse(BaseModel):
    """사용자 정보 응답 (비밀번호 제외)"""
    id: int
    username: str
    display_name: str
    role: str
    is_active: bool
    created_at: str


class UserUpdate(BaseModel):
    """사용자 정보 수정"""
    display_name: str | None = None
    role: str | None = None
    is_active: bool | None = None


class TokenResponse(BaseModel):
    """JWT 토큰 응답"""
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class PasswordChange(BaseModel):
    """비밀번호 변경"""
    current_password: str
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v):
            raise ValueError("새 비밀번호에 영문자가 포함되어야 합니다")
        if not re.search(r"[0-9]", v):
            raise ValueError("새 비밀번호에 숫자가 포함되어야 합니다")
        return v


# ============================================
# 사진 관련 모델
# ============================================

class PhotoMetadata(BaseModel):
    """사진 메타데이터 (서버 → 앱 동기화용)"""
    id: str
    filename: str
    taken_at: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    place_name: str | None = None
    is_backed_up: bool = False
    is_favorite: bool = False
    thumbnail_path: str | None = None
    persons: list[str] = []  # 태깅된 인물 이름 목록
    file_size: int | None = None
    camera_model: str | None = None


class PhotoUploadResponse(BaseModel):
    """사진 업로드 응답"""
    photo_id: str
    filename: str
    thumbnail_path: str
    storage_status: str  # "external_drive" | "buffer" | "failed"
    extracted_metadata: dict
    detected_faces: list[str]


class PhotoLocationMatch(BaseModel):
    """사진-장소 수동 매칭 요청"""
    photo_ids: list[str] = Field(..., min_length=1, description="매칭할 사진 ID 목록")
    place_name: str = Field(..., description="장소명")
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    address: str | None = None
    category: str | None = None


class FavoriteToggle(BaseModel):
    """즐겨찾기 토글"""
    photo_ids: list[str] = Field(..., min_length=1)
    is_favorite: bool


# ============================================
# 인물 관련 모델
# ============================================

class PersonCreate(BaseModel):
    """인물 등록"""
    name: str = Field(..., min_length=1, max_length=50)


class PersonResponse(BaseModel):
    """인물 정보 응답"""
    id: int
    name: str
    photo_count: int
    sample_thumbnail: str | None = None


# ============================================
# 장소 관련 모델
# ============================================

class PlaceResponse(BaseModel):
    """장소 정보 응답"""
    id: int
    name: str
    address: str | None
    latitude: float
    longitude: float
    category: str | None
    photo_count: int = 0


class PlaceSearchResult(BaseModel):
    """Nominatim 장소 검색 결과"""
    name: str
    display_name: str
    latitude: float
    longitude: float
    osm_type: str | None = None
    category: str | None = None


# ============================================
# 동기화 관련 모델
# ============================================

class SyncRequest(BaseModel):
    """동기화 요청 (앱 → 서버)"""
    last_sync_at: str | None = None  # 마지막 동기화 시간
    favorites_update: list[FavoriteToggle] | None = None


class SyncResponse(BaseModel):
    """동기화 응답 (서버 → 앱)"""
    photos: list[PhotoMetadata]
    persons: list[PersonResponse]
    places: list[PlaceResponse]
    server_time: str


# ============================================
# 시스템 상태 모델
# ============================================

class SystemStatus(BaseModel):
    """시스템 상태 정보"""
    server_running: bool = True
    external_drive_connected: bool
    external_drive_path: str
    buffer_pending_count: int  # 이관 대기 중인 파일 수
    total_photos: int
    total_persons: int
    db_size_mb: float
    thumbnail_size_mb: float
