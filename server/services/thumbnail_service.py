"""
썸네일 생성 서비스
- 원본 → 320x320px JPEG 리사이즈
- EXIF Orientation 보정
- SHA-256 해시 기반 파일명 (중복 방지)
"""

import io
import hashlib
from pathlib import Path
from PIL import Image, ImageOps

from config import settings


class ThumbnailService:
    """썸네일 생성 및 관리"""

    def __init__(self):
        self.thumb_dir = settings.thumbnail_dir
        self.width = settings.THUMBNAIL_WIDTH
        self.height = settings.THUMBNAIL_HEIGHT
        self.quality = settings.THUMBNAIL_QUALITY

    def ensure_dir(self):
        """썸네일 디렉토리 생성"""
        self.thumb_dir.mkdir(parents=True, exist_ok=True)

    def generate_file_hash(self, file_bytes: bytes) -> str:
        """파일 SHA-256 해시 생성 (사진 고유 ID)"""
        return hashlib.sha256(file_bytes).hexdigest()

    def create_thumbnail(self, image_bytes: bytes, file_hash: str) -> tuple[str, bytes]:
        """
        썸네일 생성

        Args:
            image_bytes: 원본 이미지 바이트
            file_hash: 파일 SHA-256 해시

        Returns:
            (썸네일 파일 경로, 썸네일 바이트)
        """
        self.ensure_dir()

        # 이미지 열기 및 EXIF Orientation 보정
        img = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(img)

        # RGBA → RGB 변환 (JPEG 호환)
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")

        # 비율 유지 리사이즈 (커버 크롭)
        img.thumbnail((self.width, self.height), Image.Resampling.LANCZOS)

        # 썸네일 저장
        thumb_filename = f"{file_hash}_thumb.jpg"
        thumb_path = self.thumb_dir / thumb_filename

        # 바이트로 변환
        thumb_buffer = io.BytesIO()
        img.save(thumb_buffer, format="JPEG", quality=self.quality, optimize=True)
        thumb_bytes = thumb_buffer.getvalue()

        # 파일로 저장
        with open(thumb_path, "wb") as f:
            f.write(thumb_bytes)

        return str(thumb_path), thumb_bytes

    def get_thumbnail_path(self, file_hash: str) -> Path | None:
        """기존 썸네일 경로 반환"""
        thumb_path = self.thumb_dir / f"{file_hash}_thumb.jpg"
        if thumb_path.exists():
            return thumb_path
        return None

    def delete_thumbnail(self, file_hash: str) -> bool:
        """썸네일 삭제"""
        thumb_path = self.thumb_dir / f"{file_hash}_thumb.jpg"
        if thumb_path.exists():
            thumb_path.unlink()
            return True
        return False

    def get_total_size_mb(self) -> float:
        """전체 썸네일 폴더 크기 (MB)"""
        if not self.thumb_dir.exists():
            return 0.0
        total = sum(f.stat().st_size for f in self.thumb_dir.rglob("*") if f.is_file())
        return round(total / (1024 * 1024), 2)


# 싱글톤 인스턴스
thumbnail_service = ThumbnailService()
