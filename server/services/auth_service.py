"""
인증 서비스 모듈
- bcrypt 비밀번호 해싱 (단방향, 복호화 불가)
- JWT 토큰 생성/검증
- 사용자 CRUD
"""

from datetime import datetime, timedelta, timezone
import bcrypt as _bcrypt
from jose import JWTError, jwt
from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from config import settings
from db.database import db
from models.schemas import UserCreate, UserResponse, TokenResponse


# === JWT Bearer 토큰 스키마 ===
security = HTTPBearer()


def hash_password(password: str) -> str:
    """비밀번호 → bcrypt 해시 (단방향)"""
    password_bytes = password.encode("utf-8")
    salt = _bcrypt.gensalt(rounds=settings.BCRYPT_ROUNDS)
    hashed = _bcrypt.hashpw(password_bytes, salt)
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """비밀번호 검증"""
    try:
        return _bcrypt.checkpw(
            plain_password.encode("utf-8"),
            hashed_password.encode("utf-8")
        )
    except Exception:
        return False


def create_access_token(user_id: int, username: str, role: str) -> str:
    """JWT 액세스 토큰 생성"""
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.JWT_EXPIRE_MINUTES)
    payload = {
        "sub": str(user_id),
        "username": username,
        "role": role,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    """JWT 토큰 디코드 및 검증"""
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"유효하지 않은 토큰입니다: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    """현재 인증된 사용자 반환 (의존성 주입용)"""
    payload = decode_token(credentials.credentials)
    user_id = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=401, detail="유효하지 않은 토큰입니다")

    user = await db.fetch_one("SELECT * FROM users WHERE id = ? AND is_active = 1", (int(user_id),))
    if user is None:
        raise HTTPException(status_code=401, detail="사용자를 찾을 수 없거나 비활성화된 계정입니다")

    return dict(user)


async def require_admin(current_user: dict = Depends(get_current_user)) -> dict:
    """관리자 권한 확인 (의존성 주입용)"""
    if current_user["role"] != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="관리자 권한이 필요합니다"
        )
    return current_user


# === 사용자 CRUD ===

async def create_user(user_data: UserCreate) -> dict:
    """새 사용자 생성"""
    # 중복 확인
    existing = await db.fetch_one("SELECT id FROM users WHERE username = ?", (user_data.username,))
    if existing:
        raise HTTPException(status_code=400, detail="이미 존재하는 사용자명입니다")

    # 비밀번호 해싱
    password_hash = hash_password(user_data.password)

    # DB 저장
    cursor = await db.execute(
        """INSERT INTO users (username, display_name, password_hash, role)
           VALUES (?, ?, ?, ?)""",
        (user_data.username, user_data.display_name, password_hash, user_data.role)
    )

    # 생성된 사용자 반환
    user = await db.fetch_one("SELECT * FROM users WHERE id = ?", (cursor.lastrowid,))
    return dict(user)


async def authenticate_user(username: str, password: str) -> dict:
    """사용자 인증 (로그인)"""
    user = await db.fetch_one("SELECT * FROM users WHERE username = ? AND is_active = 1", (username.lower(),))
    if not user:
        raise HTTPException(status_code=401, detail="사용자명 또는 비밀번호가 올바르지 않습니다")

    if not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="사용자명 또는 비밀번호가 올바르지 않습니다")

    return dict(user)


async def get_all_users() -> list[dict]:
    """모든 사용자 목록 조회"""
    users = await db.fetch_all("SELECT * FROM users ORDER BY created_at")
    return [dict(u) for u in users]


async def update_user(user_id: int, **kwargs) -> dict:
    """사용자 정보 수정"""
    updates = []
    params = []
    for key, value in kwargs.items():
        if value is not None:
            updates.append(f"{key} = ?")
            params.append(value)

    if not updates:
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다")

    updates.append("updated_at = CURRENT_TIMESTAMP")
    params.append(user_id)

    await db.execute(
        f"UPDATE users SET {', '.join(updates)} WHERE id = ?",
        tuple(params)
    )

    user = await db.fetch_one("SELECT * FROM users WHERE id = ?", (user_id,))
    if not user:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")
    return dict(user)


async def delete_user(user_id: int):
    """사용자 삭제 (비활성화)"""
    await db.execute("UPDATE users SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?", (user_id,))


async def change_password(user_id: int, current_password: str, new_password: str):
    """비밀번호 변경"""
    user = await db.fetch_one("SELECT * FROM users WHERE id = ?", (user_id,))
    if not user:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")

    if not verify_password(current_password, user["password_hash"]):
        raise HTTPException(status_code=400, detail="현재 비밀번호가 올바르지 않습니다")

    new_hash = hash_password(new_password)
    await db.execute(
        "UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        (new_hash, user_id)
    )


async def ensure_admin_exists():
    """최초 실행 시 기본 관리자 계정 생성"""
    admin = await db.fetch_one("SELECT id FROM users WHERE role = 'admin' LIMIT 1")
    if not admin:
        default_admin = UserCreate(
            username="admin",
            password="Admin1234!",  # 최초 비밀번호 (변경 필수)
            display_name="관리자",
            role="admin"
        )
        await create_user(default_admin)
        print("⚠️  기본 관리자 계정 생성됨 (ID: admin / PW: Admin1234!) — 즉시 변경하세요!")
