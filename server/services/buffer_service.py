"""
임시 버퍼 관리 서비스
- 외장하드 미연결 시 임시 폴더에 사진 보관
- 외장하드 연결 감지 시 자동 이관
- 이관 실패 시 재시도 큐 관리
"""

import shutil
import asyncio
from pathlib import Path
from datetime import datetime

from config import settings
from db.database import db
from services.storage_service import storage_service


class BufferService:
    """임시 버퍼(대기실) 관리"""

    def __init__(self):
        self.buffer_path = Path(settings.TEMP_BUFFER_PATH)

    def ensure_dir(self):
        """버퍼 디렉토리 생성"""
        self.buffer_path.mkdir(parents=True, exist_ok=True)

    def save_to_buffer(self, file_bytes: bytes, filename: str) -> str:
        """
        사진을 임시 버퍼에 저장

        Returns:
            저장된 파일 경로
        """
        self.ensure_dir()
        file_path = self.buffer_path / filename

        # 동일 파일 존재 시 타임스탬프 추가
        if file_path.exists():
            stem = file_path.stem
            suffix = file_path.suffix
            timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
            file_path = self.buffer_path / f"{stem}_{timestamp}{suffix}"

        with open(file_path, "wb") as f:
            f.write(file_bytes)

        print(f"📦 버퍼 저장: {file_path}")
        return str(file_path)

    async def add_to_queue(self, photo_id: str, buffer_file_path: str, target_folder: str):
        """이관 큐에 추가"""
        await db.execute(
            """INSERT INTO buffer_queue (photo_id, buffer_file_path, target_folder, status)
               VALUES (?, ?, ?, 'pending')""",
            (photo_id, buffer_file_path, target_folder)
        )

    async def process_pending_queue(self) -> dict:
        """
        대기 중인 버퍼 파일들을 외장하드로 이관

        Returns:
            {"transferred": 3, "failed": 1, "remaining": 0}
        """
        if not storage_service.is_drive_connected():
            return {"transferred": 0, "failed": 0, "remaining": -1, "message": "외장하드 미연결"}

        pending = await db.fetch_all(
            """SELECT * FROM buffer_queue
               WHERE status IN ('pending', 'failed')
               AND retry_count < 3
               ORDER BY created_at"""
        )

        transferred = 0
        failed = 0

        for item in pending:
            buffer_path = Path(item["buffer_file_path"])

            if not buffer_path.exists():
                # 버퍼 파일이 없으면 실패 처리
                await db.execute(
                    "UPDATE buffer_queue SET status = 'failed' WHERE id = ?",
                    (item["id"],)
                )
                failed += 1
                continue

            # 외장하드 대상 폴더 생성
            target_folder = Path(settings.EXTERNAL_DRIVE_PATH) / item["target_folder"]

            # 이관 시도
            await db.execute(
                "UPDATE buffer_queue SET status = 'transferring' WHERE id = ?",
                (item["id"],)
            )

            result = storage_service.save_to_external(
                str(buffer_path),
                target_folder,
                buffer_path.name
            )

            if result:
                # 이관 성공
                await db.execute(
                    """UPDATE buffer_queue
                       SET status = 'done', transferred_at = CURRENT_TIMESTAMP
                       WHERE id = ?""",
                    (item["id"],)
                )

                # photos 테이블 업데이트
                await db.execute(
                    """UPDATE photos
                       SET is_backed_up = 1, original_path = ?, buffer_path = NULL
                       WHERE id = ?""",
                    (result, item["photo_id"])
                )

                # 버퍼 파일 삭제
                try:
                    buffer_path.unlink()
                    print(f"🗑️ 버퍼 파일 삭제: {buffer_path}")
                except Exception:
                    pass

                transferred += 1
            else:
                # 이관 실패 → 재시도 카운트 증가
                await db.execute(
                    """UPDATE buffer_queue
                       SET status = 'failed', retry_count = retry_count + 1
                       WHERE id = ?""",
                    (item["id"],)
                )
                failed += 1

        remaining = await db.fetch_one(
            "SELECT COUNT(*) as cnt FROM buffer_queue WHERE status IN ('pending', 'failed') AND retry_count < 3"
        )

        return {
            "transferred": transferred,
            "failed": failed,
            "remaining": remaining["cnt"] if remaining else 0,
        }

    async def get_pending_count(self) -> int:
        """대기 중인 파일 수"""
        result = await db.fetch_one(
            "SELECT COUNT(*) as cnt FROM buffer_queue WHERE status IN ('pending', 'failed') AND retry_count < 3"
        )
        return result["cnt"] if result else 0

    def get_buffer_size_mb(self) -> float:
        """버퍼 폴더 크기 (MB)"""
        if not self.buffer_path.exists():
            return 0.0
        total = sum(f.stat().st_size for f in self.buffer_path.rglob("*") if f.is_file())
        return round(total / (1024 * 1024), 2)


# 싱글톤 인스턴스
buffer_service = BufferService()
