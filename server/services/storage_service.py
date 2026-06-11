"""
외장하드 저장소 서비스
- 년-월-일_장소명 폴더 자동 생성
- 원본 파일 이동/복사
- 파일 무결성 검증 (SHA-256 해시 비교)
"""

import shutil
import hashlib
from pathlib import Path
from datetime import datetime

from config import settings


class StorageService:
    """외장하드 파일 관리 서비스"""

    def __init__(self):
        self.external_path = Path(settings.EXTERNAL_DRIVE_PATH)

    def is_drive_connected(self) -> bool:
        """외장하드 연결 여부 확인"""
        try:
            return self.external_path.exists() and self.external_path.is_dir()
        except (OSError, PermissionError):
            return False

    def get_target_folder(self, taken_at: str | None, place_name: str | None) -> Path:
        """
        저장 대상 폴더 경로 생성 (2단계 구조: 날짜/장소)

        형식: X:/2024-03-15/하남스타필드/
        GPS 없을 경우: X:/2024-03-15/위치미상/
        날짜 없을 경우: X:/날짜미상/위치미상/
        """
        if taken_at:
            try:
                dt = datetime.fromisoformat(taken_at)
                date_str = f"{dt.year:04d}-{dt.month:02d}-{dt.day:02d}"
            except (ValueError, TypeError):
                date_str = "날짜미상"
        else:
            date_str = "날짜미상"

        # 장소명 정리 (파일시스템 금지 문자 제거)
        if place_name:
            safe_name = self._sanitize_folder_name(place_name)
        else:
            safe_name = "위치미상"

        return self.external_path / date_str / safe_name

    def save_to_external(self, source_path: str, target_folder: Path, filename: str) -> str | None:
        """
        파일을 외장하드에 저장

        Args:
            source_path: 원본/버퍼 파일 경로
            target_folder: 대상 폴더 (년-월-일_장소명)
            filename: 저장할 파일명

        Returns:
            저장된 파일의 전체 경로 또는 None (실패 시)
        """
        try:
            # 폴더 생성
            target_folder.mkdir(parents=True, exist_ok=True)

            # 대상 경로
            target_path = target_folder / filename

            # 동일 파일 존재 시 스킵
            if target_path.exists():
                print(f"ℹ️ 이미 존재하는 파일: {target_path}")
                return str(target_path)

            # 파일 복사
            shutil.copy2(str(source_path), str(target_path))

            # 무결성 검증
            if self._verify_integrity(str(source_path), str(target_path)):
                print(f"✅ 외장하드 저장 완료: {target_path}")
                return str(target_path)
            else:
                # 무결성 실패 → 대상 파일 삭제
                target_path.unlink(missing_ok=True)
                print(f"❌ 무결성 검증 실패: {target_path}")
                return None

        except Exception as e:
            print(f"❌ 외장하드 저장 실패: {e}")
            return None

    def _verify_integrity(self, source: str, target: str) -> bool:
        """파일 무결성 검증 (SHA-256 해시 비교)"""
        try:
            source_hash = self._file_hash(source)
            target_hash = self._file_hash(target)
            return source_hash == target_hash
        except Exception:
            return False

    @staticmethod
    def _file_hash(filepath: str) -> str:
        """파일 SHA-256 해시 계산"""
        sha256 = hashlib.sha256()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                sha256.update(chunk)
        return sha256.hexdigest()

    @staticmethod
    def _sanitize_folder_name(name: str) -> str:
        """폴더명에 사용 불가한 문자 제거"""
        forbidden = '<>:"/\\|?*'
        sanitized = "".join(c if c not in forbidden else "_" for c in name)
        # 연속 밑줄 정리 및 앞뒤 공백 제거
        import re
        sanitized = re.sub(r"_+", "_", sanitized).strip("_. ")
        return sanitized[:50]  # 폴더명 길이 제한

    def get_drive_info(self) -> dict:
        """외장하드 정보"""
        if not self.is_drive_connected():
            return {"connected": False, "path": str(self.external_path)}

        try:
            import psutil
            for partition in psutil.disk_partitions(all=True):
                if self.external_path.as_posix().startswith(partition.mountpoint.replace("\\", "/")):
                    usage = psutil.disk_usage(partition.mountpoint)
                    return {
                        "connected": True,
                        "path": str(self.external_path),
                        "total_gb": round(usage.total / (1024**3), 2),
                        "used_gb": round(usage.used / (1024**3), 2),
                        "free_gb": round(usage.free / (1024**3), 2),
                        "percent_used": usage.percent,
                    }
        except Exception:
            pass

        return {"connected": True, "path": str(self.external_path)}


# 싱글톤 인스턴스
storage_service = StorageService()
