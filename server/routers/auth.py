"""
사용자 관리 API 라우터
- 사용자 등록 / 로그인 / 목록 조회
- 비밀번호 변경 / 사용자 수정 / 삭제
- JWT 인증 + 역할 기반 접근 제어
"""

from fastapi import APIRouter, Depends
from models.schemas import (
    UserCreate, UserLogin, UserResponse, UserUpdate,
    TokenResponse, PasswordChange,
)
from services.auth_service import (
    create_user, authenticate_user, create_access_token,
    get_current_user, require_admin, get_all_users,
    update_user, delete_user, change_password,
)

router = APIRouter(prefix="/api/auth", tags=["사용자 관리"])


@router.post("/register", response_model=TokenResponse)
async def register(user_data: UserCreate, admin: dict = Depends(require_admin)):
    """
    새 사용자 등록 (관리자 전용)

    - 관리자만 새 가족 구성원을 등록할 수 있음
    - 비밀번호는 bcrypt로 해싱 후 저장
    """
    user = await create_user(user_data)
    token = create_access_token(user["id"], user["username"], user["role"])

    return TokenResponse(
        access_token=token,
        user=UserResponse(
            id=user["id"],
            username=user["username"],
            display_name=user["display_name"],
            role=user["role"],
            is_active=bool(user["is_active"]),
            created_at=str(user["created_at"]),
        )
    )


@router.post("/login", response_model=TokenResponse)
async def login(credentials: UserLogin):
    """
    로그인

    - 사용자명 + 비밀번호 검증
    - 성공 시 JWT 토큰 반환
    """
    user = await authenticate_user(credentials.username, credentials.password)
    token = create_access_token(user["id"], user["username"], user["role"])

    return TokenResponse(
        access_token=token,
        user=UserResponse(
            id=user["id"],
            username=user["username"],
            display_name=user["display_name"],
            role=user["role"],
            is_active=bool(user["is_active"]),
            created_at=str(user["created_at"]),
        )
    )


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: dict = Depends(get_current_user)):
    """현재 로그인한 사용자 정보"""
    return UserResponse(
        id=current_user["id"],
        username=current_user["username"],
        display_name=current_user["display_name"],
        role=current_user["role"],
        is_active=bool(current_user["is_active"]),
        created_at=str(current_user["created_at"]),
    )


@router.get("/users", response_model=list[UserResponse])
async def list_users(admin: dict = Depends(require_admin)):
    """모든 사용자 목록 (관리자 전용)"""
    users = await get_all_users()
    return [
        UserResponse(
            id=u["id"],
            username=u["username"],
            display_name=u["display_name"],
            role=u["role"],
            is_active=bool(u["is_active"]),
            created_at=str(u["created_at"]),
        )
        for u in users
    ]


@router.put("/users/{user_id}", response_model=UserResponse)
async def edit_user(user_id: int, data: UserUpdate, admin: dict = Depends(require_admin)):
    """사용자 정보 수정 (관리자 전용)"""
    update_data = {}
    if data.display_name is not None:
        update_data["display_name"] = data.display_name
    if data.role is not None:
        update_data["role"] = data.role
    if data.is_active is not None:
        update_data["is_active"] = int(data.is_active)

    user = await update_user(user_id, **update_data)
    return UserResponse(
        id=user["id"],
        username=user["username"],
        display_name=user["display_name"],
        role=user["role"],
        is_active=bool(user["is_active"]),
        created_at=str(user["created_at"]),
    )


@router.delete("/users/{user_id}")
async def remove_user(user_id: int, admin: dict = Depends(require_admin)):
    """사용자 삭제/비활성화 (관리자 전용)"""
    await delete_user(user_id)
    return {"message": f"사용자 {user_id} 비활성화 완료"}


@router.put("/password")
async def update_password(data: PasswordChange, current_user: dict = Depends(get_current_user)):
    """비밀번호 변경 (본인 전용)"""
    await change_password(current_user["id"], data.current_password, data.new_password)
    return {"message": "비밀번호가 변경되었습니다"}
