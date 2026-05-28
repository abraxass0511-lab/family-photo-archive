"""
외장하드 연결 감지 워처
- psutil로 마운트된 디스크 실시간 감시 (5초 간격)
- 외장하드 감지 시 버퍼 → 외장하드 자동 이관 트리거
- Windows (X:/) 및 Linux (/mnt/usb) 양쪽 호환
"""

import asyncio
import psutil
from pathlib import Path

from config import settings
from services.buffer_service import buffer_service
from services.storage_service import storage_service


class DriveWatcher:
    """외장하드 연결 감지 및 자동 이관 워처"""

    def __init__(self):
        self.external_path = Path(settings.EXTERNAL_DRIVE_PATH)
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
        - 임시 버퍼의 모든 대기 파일을 외장하드로 이관
        """
        pending_count = await buffer_service.get_pending_count()

        if pending_count == 0:
            print("📭 이관 대기 중인 파일 없음")
            return

        print(f"📦 {pending_count}개 파일 이관 시작...")
        result = await buffer_service.process_pending_queue()

        print(f"✅ 이관 완료: {result['transferred']}건 성공, "
              f"{result['failed']}건 실패, "
              f"{result['remaining']}건 잔여")

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
