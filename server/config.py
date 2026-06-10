"""
설정 관리 모듈
- 모든 경로를 환경변수로 관리하여 라즈베리파이 이식 가능
- .env 파일 또는 환경변수로 오버라이드 가능
"""

import os
import secrets
from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """앱 전체 설정"""

    # === 서버 설정 ===
    APP_NAME: str = "가족 추억 보관 상자"
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = True

    # === 보안 설정 ===
    SECRET_KEY: str = secrets.token_urlsafe(64)
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 1440  # 24시간
    BCRYPT_ROUNDS: int = 12  # bcrypt 해싱 라운드 (보안 강도)

    # === 저장소 경로 (라즈베리파이 이식 대비: 환경변수로 변경 가능) ===
    # Windows: "X:/" | Linux/RPi: "/mnt/usb"
    EXTERNAL_DRIVE_PATH: str = "D:/가족사진"
    # 사진 임시 저장 (외장하드 연결 시 자동 이동)
    TEMP_BUFFER_PATH: str = str(Path.home() / "Desktop" / "사진모음집")
    # 서버 내부 데이터 (DB, 썸네일 등)
    DATA_DIR: str = str(Path.home() / "Desktop" / "사진모음집" / "data")
    # 얼굴 인식 학습 데이터
    FACE_DATA_DIR: str = str(Path.home() / "Desktop" / "사진모음집" / "faces")

    # === 썸네일 설정 ===
    THUMBNAIL_WIDTH: int = 320
    THUMBNAIL_HEIGHT: int = 320
    THUMBNAIL_QUALITY: int = 75  # JPEG 품질 (1~100)

    # === 외장하드 감지 ===
    DRIVE_CHECK_INTERVAL: int = 5  # 초 단위 감시 간격

    # === 폴더 생성 형식 ===
    FOLDER_FORMAT: str = "{year:04d}-{month:02d}-{day:02d}_{place_name}"

    # === Nominatim (100% 무료 지오코딩) ===
    NOMINATIM_USER_AGENT: str = "family-photo-archive/1.0"
    NOMINATIM_RATE_LIMIT: float = 1.0  # 초당 최대 1요청 (정책 준수)


    # === 카카오 로컬 API (100% 무료, 일 10만 건) ===
    # https://developers.kakao.com 에서 무료 앱 등록 후 REST API 키 입력
    KAKAO_REST_API_KEY: str = ""

    # === 정적 웹 배포 ===
    WEB_BUILD_DIR: str = str(Path.home() / "PhotoBuffer" / "web_build")
    WEB_PASSWORD_HASH: str = ""  # 공유 웹사이트 암호 해시
    # AES-256 암호화 키 (배포 시 자동 생성)
    WEB_ENCRYPTION_SALT: str = "family-photo-archive-aes-salt"

    # === Cloudflare Pages 배포 (100% 무료) ===
    CLOUDFLARE_PROJECT_NAME: str = "family-photo-archive"
    # Wrangler CLI 토큰 (선택적 — 없으면 GitHub Pages 사용)
    CLOUDFLARE_API_TOKEN: str = ""

    # === CORS 허용 도메인 ===
    ALLOWED_ORIGINS: list[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
    ]

    @property
    def database_url(self) -> str:
        """SQLite DB 파일 경로"""
        db_path = Path(self.DATA_DIR) / "photo_archive.db"
        return f"sqlite+aiosqlite:///{db_path}"

    @property
    def db_path(self) -> Path:
        """DB 파일 절대 경로"""
        return Path(self.DATA_DIR) / "photo_archive.db"

    @property
    def thumbnail_dir(self) -> Path:
        """썸네일 저장 디렉토리"""
        return Path(self.DATA_DIR) / "thumbnails"

    def ensure_dirs(self):
        """필요한 디렉토리 자동 생성"""
        for dir_path in [
            self.TEMP_BUFFER_PATH,
            self.DATA_DIR,
            self.FACE_DATA_DIR,
            str(self.thumbnail_dir),
            self.WEB_BUILD_DIR,
        ]:
            Path(dir_path).mkdir(parents=True, exist_ok=True)

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


# 싱글톤 설정 인스턴스
settings = Settings()
