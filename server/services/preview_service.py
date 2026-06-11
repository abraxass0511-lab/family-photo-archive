"""
동영상 미리보기 생성 서비스
- FFmpeg로 360p 저화질 MP4 변환
- 핸드폰 로컬 저장용 (오프라인 재생)
- FFmpeg 미설치 시 자동 스킵
"""

import subprocess
import shutil
import tempfile
from pathlib import Path

from config import settings


class PreviewService:
    """동영상 미리보기(360p MP4) 생성 및 관리"""

    def __init__(self):
        self.preview_dir = settings.thumbnail_dir  # 썸네일과 같은 디렉토리
        self._ffmpeg_path = shutil.which("ffmpeg")

    @property
    def is_available(self) -> bool:
        """FFmpeg 설치 여부"""
        return self._ffmpeg_path is not None

    def create_preview(self, video_bytes: bytes, file_hash: str) -> str | None:
        """
        동영상 → 360p 미리보기 MP4 생성

        Args:
            video_bytes: 원본 동영상 바이트
            file_hash: 파일 SHA-256 해시

        Returns:
            미리보기 파일 경로 (실패 시 None)
        """
        if not self.is_available:
            print("⚠️ FFmpeg 미설치 — 동영상 미리보기 생성 스킵")
            return None

        preview_filename = f"{file_hash}_preview.mp4"
        preview_path = self.preview_dir / preview_filename

        # 이미 존재하면 재생성 불필요
        if preview_path.exists():
            return str(preview_path)

        self.preview_dir.mkdir(parents=True, exist_ok=True)

        # 원본을 임시 파일로 저장
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(video_bytes)
            tmp_input = tmp.name

        # 출력도 임시 파일로 (한글 경로 문제 우회)
        tmp_output = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False)
        tmp_output_path = tmp_output.name
        tmp_output.close()

        try:
            # FFmpeg 변환: 360p, 저비트레이트
            cmd = [
                self._ffmpeg_path,
                "-i", tmp_input,
                "-vf", "scale=-2:360",      # 높이 360px, 너비 자동 (짝수)
                "-b:v", "300k",              # 비디오 비트레이트 300kbps
                "-c:v", "libx264",           # H.264 코덱
                "-preset", "fast",           # 빠른 인코딩
                "-c:a", "aac",               # 오디오 AAC
                "-b:a", "48k",               # 오디오 48kbps
                "-movflags", "+faststart",   # 스트리밍 최적화
                "-y",                        # 덮어쓰기
                tmp_output_path,
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120,  # 2분 타임아웃
            )

            if result.returncode != 0:
                print(f"⚠️ 미리보기 생성 실패 ({file_hash[:16]}): {result.stderr[-200:]}")
                return None

            # 임시 파일 → 최종 위치로 이동
            shutil.move(tmp_output_path, str(preview_path))
            size_mb = preview_path.stat().st_size / 1024 / 1024
            print(f"🎬 미리보기 생성: {file_hash[:16]}... ({size_mb:.1f}MB)")
            return str(preview_path)

        except subprocess.TimeoutExpired:
            print(f"⚠️ 미리보기 생성 타임아웃: {file_hash[:16]}")
            return None
        except Exception as e:
            print(f"⚠️ 미리보기 생성 오류: {e}")
            return None
        finally:
            # 임시 파일 정리
            Path(tmp_input).unlink(missing_ok=True)
            Path(tmp_output_path).unlink(missing_ok=True)

    def create_preview_from_file(self, video_path: str | Path, file_hash: str) -> str | None:
        """
        파일 경로에서 직접 미리보기 생성 (마이그레이션용)
        바이트를 메모리에 올리지 않고 파일을 직접 참조
        """
        if not self.is_available:
            print("⚠️ FFmpeg 미설치 — 동영상 미리보기 생성 스킵")
            return None

        video_path = Path(video_path)
        if not video_path.exists():
            return None

        preview_filename = f"{file_hash}_preview.mp4"
        preview_path = self.preview_dir / preview_filename

        if preview_path.exists():
            return str(preview_path)

        self.preview_dir.mkdir(parents=True, exist_ok=True)

        # 출력용 임시 파일
        tmp_output = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False)
        tmp_output_path = tmp_output.name
        tmp_output.close()

        try:
            cmd = [
                self._ffmpeg_path,
                "-i", str(video_path),
                "-vf", "scale=-2:360",
                "-b:v", "300k",
                "-c:v", "libx264",
                "-preset", "fast",
                "-c:a", "aac",
                "-b:a", "48k",
                "-movflags", "+faststart",
                "-y",
                tmp_output_path,
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120,
            )

            if result.returncode != 0:
                print(f"⚠️ 미리보기 생성 실패: {video_path.name}")
                return None

            shutil.move(tmp_output_path, str(preview_path))
            size_mb = preview_path.stat().st_size / 1024 / 1024
            print(f"🎬 미리보기 생성: {video_path.name} → {size_mb:.1f}MB")
            return str(preview_path)

        except Exception as e:
            print(f"⚠️ 미리보기 생성 오류: {e}")
            return None
        finally:
            Path(tmp_output_path).unlink(missing_ok=True)

    def get_preview_path(self, file_hash: str) -> Path | None:
        """기존 미리보기 경로 반환"""
        preview_path = self.preview_dir / f"{file_hash}_preview.mp4"
        if preview_path.exists():
            return preview_path
        return None

    def delete_preview(self, file_hash: str) -> bool:
        """미리보기 삭제"""
        preview_path = self.preview_dir / f"{file_hash}_preview.mp4"
        if preview_path.exists():
            preview_path.unlink()
            return True
        return False


# 싱글톤 인스턴스
preview_service = PreviewService()
