"""
임시 버퍼 관리 서비스
- 외장하드 미연결 시 임시 폴더에 사진 보관
- 외장하드 연결 감지 시 자동 이관
- 이관 실패 시 재시도 큐 관리
"""

import shutil
import asyncio
from send2trash import send2trash
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

    def save_to_buffer(self, file_bytes: bytes, filename: str, file_hash: str = None) -> str:
        """
        사진을 임시 버퍼에 저장 (원본 파일명 유지)

        Args:
            file_bytes: 파일 바이트
            filename: 원본 파일명
            file_hash: 파일 해시 (중복 방지용)

        Returns:
            저장된 파일 경로
        """
        self.ensure_dir()

        # 원본 파일명 그대로 사용
        file_path = self.buffer_path / filename

        # 이미 동일 파일이 있으면 저장 건너뛰기
        if file_path.exists():
            print(f"📦 버퍼 기존 파일 사용: {file_path}")
            return str(file_path)

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

            # 하위호환: 기존 flat 형식 "2026-05-27_장소명" → 중첩 "2026-05-27/장소명"
            target_folder_str = item["target_folder"]
            if "/" not in target_folder_str and "\\" not in target_folder_str:
                parts = target_folder_str.split("_", 1)
                if len(parts) == 2:
                    target_folder_str = parts[0] + "/" + parts[1]

            if not buffer_path.exists():
                # 버퍼 파일이 없으면 실패 처리
                await db.execute(
                    "UPDATE buffer_queue SET status = 'failed' WHERE id = ?",
                    (item["id"],)
                )
                failed += 1
                continue

            # 외장하드 대상 폴더 생성
            target_folder = Path(settings.EXTERNAL_DRIVE_PATH) / target_folder_str

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

                # 버퍼 파일을 휴지통으로 이동 (복원 가능)
                try:
                    send2trash(str(buffer_path))
                    print(f"🗑️ 버퍼 파일 → 휴지통: {buffer_path}")
                except Exception:
                    try:
                        buffer_path.unlink()
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
        """대기 중인 파일 수 (실제 파일 존재 여부 확인)"""
        pending = await db.fetch_all(
            "SELECT id, photo_id, buffer_file_path FROM buffer_queue WHERE status IN ('pending', 'failed') AND retry_count < 3"
        )

        actual_count = 0
        for item in pending:
            if Path(item["buffer_file_path"]).exists():
                actual_count += 1
            else:
                # 파일이 삭제되었으면 DB 기록도 정리
                await db.execute("DELETE FROM buffer_queue WHERE id = ?", (item["id"],))
                await db.execute("DELETE FROM photo_persons WHERE photo_id = ?", (item["photo_id"],))
                await db.execute("DELETE FROM photo_places WHERE photo_id = ?", (item["photo_id"],))
                await db.execute("DELETE FROM photos WHERE id = ?", (item["photo_id"],))
                print(f"🧹 삭제된 파일 DB 정리: {item['buffer_file_path']}")

        return actual_count

    def get_buffer_size_mb(self) -> float:
        """버퍼 폴더 크기 (MB)"""
        if not self.buffer_path.exists():
            return 0.0
        total = sum(f.stat().st_size for f in self.buffer_path.rglob("*") if f.is_file())
        return round(total / (1024 * 1024), 2)


# 싱글톤 인스턴스
buffer_service = BufferService()
