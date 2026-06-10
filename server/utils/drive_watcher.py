"""
외장하드 연결 감지 + 폴더 감시 워처
- psutil로 마운트된 디스크 실시간 감시 (5초 간격)
- 버퍼 폴더에 직접 넣은 파일도 자동 이관
- 외장하드 감지 시 버퍼 → 외장하드 자동 이관 트리거
"""

import asyncio
import shutil
import psutil
from send2trash import send2trash
from pathlib import Path

from config import settings
from services.buffer_service import buffer_service
from services.storage_service import storage_service


# 이관 대상 확장자
MEDIA_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".bmp", ".gif",
    ".mp4", ".mov", ".avi", ".mkv", ".webm", ".3gp",
}


class DriveWatcher:
    """외장하드 연결 감지 + 폴더 감시 워처"""

    def __init__(self):
        self.external_path = Path(settings.EXTERNAL_DRIVE_PATH)
        self.buffer_path = Path(settings.TEMP_BUFFER_PATH)
        self.check_interval = settings.DRIVE_CHECK_INTERVAL
        self._running = False
        self._was_connected = False
        self._task: asyncio.Task | None = None

    async def start(self):
        """워처 시작 (백그라운드 태스크)"""
        if self._running:
            return

        self._running = True
        self._was_connected = storage_service.is_drive_connected()
        self._task = asyncio.create_task(self._watch_loop())

        status = "🟢 연결됨" if self._was_connected else "🔴 미연결"
        print(f"👁️ 외장하드 감지 워처 시작 (경로: {self.external_path}, 상태: {status})")
        print(f"📂 폴더 감시 활성: {self.buffer_path}")

        # 서버 시작 시 이미 외장하드가 연결되어 있으면 즉시 pending 큐 처리
        if self._was_connected:
            asyncio.create_task(self._on_drive_connected())

    async def stop(self):
        """워처 중지"""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        print("🛑 외장하드 감지 워처 중지")

    async def _watch_loop(self):
        """주기적 감시 루프"""
        while self._running:
            try:
                is_connected = storage_service.is_drive_connected()

                if is_connected and not self._was_connected:
                    # 🎉 외장하드가 새로 연결됨!
                    print(f"🔌 외장하드 연결 감지! ({self.external_path})")
                    await self._on_drive_connected()

                elif is_connected:
                    # 이미 연결된 상태: pending 큐 + 폴더 직접 넣은 파일 모두 처리
                    pending_count = await buffer_service.get_pending_count()
                    if pending_count > 0:
                        result = await buffer_service.process_pending_queue()
                        if result['transferred'] > 0:
                            print(f"✅ 자동 이관: {result['transferred']}건 완료, "
                                  f"{result['failed']}건 실패, "
                                  f"{result['remaining']}건 잔여")
                    await self._transfer_folder_files()

                elif not is_connected and self._was_connected:
                    # 외장하드 분리됨
                    print(f"⚡ 외장하드 분리됨 ({self.external_path})")

                self._was_connected = is_connected

            except Exception as e:
                print(f"⚠️ 드라이브 감시 오류: {e}")

            await asyncio.sleep(self.check_interval)

    async def _on_drive_connected(self):
        """
        외장하드 연결 시 실행되는 콜백
        - DB 큐의 대기 파일 이관
        - 폴더에 직접 넣은 파일도 이관
        """
        # 1. DB 큐에 등록된 파일 이관
        pending_count = await buffer_service.get_pending_count()
        if pending_count > 0:
            print(f"📦 {pending_count}개 파일 이관 시작...")
            result = await buffer_service.process_pending_queue()
            print(f"✅ 이관 완료: {result['transferred']}건 성공, "
                  f"{result['failed']}건 실패, "
                  f"{result['remaining']}건 잔여")

        # 2. 폴더에 직접 넣은 파일도 이관
        await self._transfer_folder_files()

    async def _transfer_folder_files(self):
        """
        버퍼 폴더의 미디어 파일을 외장하드로 직접 이관
        (DB 큐에 등록되지 않은 파일 = 사용자가 직접 넣은 파일)
        주의: upload API가 처리한 파일은 건너뜀
        """
        if not self.buffer_path.exists():
            return

        # 폴더 내 미디어 파일 목록
        media_files = [
            f for f in self.buffer_path.iterdir()
            if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS
        ]

        if not media_files:
            return

        # DB에 등록된 파일 목록 가져오기 (upload API가 처리한 파일)
        from db.database import db
        db_files = set()
        try:
            rows = await db.fetch_all("SELECT filename FROM photos")
            db_files = {row[0] for row in rows}
        except Exception:
            pass

        # DB에 등록된 파일은 건너뜀 (upload API가 이관 담당)
        orphan_files = [f for f in media_files if f.name not in db_files]
        
        if not orphan_files:
            return

        # 외장하드 대상 폴더 (직접 넣은 파일은 "직접전송" 폴더로)
        target_folder = self.external_path / "직접전송"

        transferred = 0
        for file_path in orphan_files:
            try:
                result = storage_service.save_to_external(
                    str(file_path), target_folder, file_path.name
                )
                if result:
                    # 원본을 휴지통으로 이동 (복원 가능)
                    try:
                        send2trash(str(file_path))
                    except Exception:
                        file_path.unlink()  # fallback: 휴지통 실패 시 영구삭제
                    transferred += 1
                    print(f"📤 직접 이관 완료: {file_path.name} → {target_folder} (원본 → 휴지통)")
            except Exception as e:
                print(f"⚠️ 직접 이관 실패 ({file_path.name}): {e}")

        if transferred:
            print(f"✅ 폴더 직접 이관: {transferred}개 완료")

    def get_mounted_drives(self) -> list[dict]:
        """현재 마운트된 드라이브 목록"""
        drives = []
        for partition in psutil.disk_partitions(all=True):
            try:
                usage = psutil.disk_usage(partition.mountpoint)
                drives.append({
                    "device": partition.device,
                    "mountpoint": partition.mountpoint,
                    "fstype": partition.fstype,
                    "total_gb": round(usage.total / (1024**3), 2),
                    "free_gb": round(usage.free / (1024**3), 2),
                })
            except (PermissionError, OSError):
                drives.append({
                    "device": partition.device,
                    "mountpoint": partition.mountpoint,
                    "fstype": partition.fstype,
                    "total_gb": 0,
                    "free_gb": 0,
                })
        return drives


# 싱글톤 인스턴스
drive_watcher = DriveWatcher()

