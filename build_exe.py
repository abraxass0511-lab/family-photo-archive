"""
PyInstaller 빌드 스크립트
- Python 백엔드 → 원클릭 .exe 인스톨러
- 일반 소비자가 설치/실행 가능하도록 패키징
"""

import subprocess
import sys
import shutil
from pathlib import Path


def build_exe():
    """PyInstaller로 .exe 빌드"""
    server_dir = Path(__file__).parent / "server"
    dist_dir = Path(__file__).parent / "dist"
    build_dir = Path(__file__).parent / "build"

    print("=" * 60)
    print("🏗️  가족 추억 보관 상자 — .exe 빌드")
    print("=" * 60)

    # 1. PyInstaller 설치 확인
    try:
        import PyInstaller
        print(f"✅ PyInstaller {PyInstaller.__version__} 확인됨")
    except ImportError:
        print("📦 PyInstaller 설치 중...")
        subprocess.run([sys.executable, "-m", "pip", "install", "pyinstaller"],
                       check=True)
        print("✅ PyInstaller 설치 완료")

    # 2. 빌드 정리
    for d in [dist_dir, build_dir]:
        if d.exists():
            shutil.rmtree(d)
            print(f"🧹 {d} 정리됨")

    # 3. PyInstaller 실행
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--name", "가족추억보관상자",
        "--onedir",                      # 폴더 형태 (onefile보다 빠른 시작)
        "--noconsole",                    # 콘솔 창 숨김
        "--icon", str(server_dir / "assets" / "icon.ico"),  # 아이콘 (있으면)
        "--add-data", f"{server_dir / 'services'};services",
        "--add-data", f"{server_dir / 'routers'};routers",
        "--add-data", f"{server_dir / 'db'};db",
        "--add-data", f"{server_dir / 'models'};models",
        "--add-data", f"{server_dir / 'utils'};utils",
        # 히든 임포트 (동적 로딩 모듈)
        "--hidden-import", "uvicorn.logging",
        "--hidden-import", "uvicorn.loops",
        "--hidden-import", "uvicorn.loops.auto",
        "--hidden-import", "uvicorn.protocols",
        "--hidden-import", "uvicorn.protocols.http",
        "--hidden-import", "uvicorn.protocols.http.auto",
        "--hidden-import", "uvicorn.protocols.websockets",
        "--hidden-import", "uvicorn.protocols.websockets.auto",
        "--hidden-import", "uvicorn.lifespan",
        "--hidden-import", "uvicorn.lifespan.on",
        "--hidden-import", "aiosqlite",
        "--hidden-import", "bcrypt",
        "--hidden-import", "PIL",
        "--hidden-import", "geopy",
        "--hidden-import", "face_recognition",
        "--hidden-import", "cryptography",
        # 엔트리포인트
        str(server_dir / "main.py"),
    ]

    # 아이콘 파일이 없으면 --icon 옵션 제거
    icon_path = server_dir / "assets" / "icon.ico"
    if not icon_path.exists():
        cmd = [c for c in cmd if c != str(icon_path) and c != "--icon"]

    print("\n🔨 빌드 시작...")
    print(f"   명령어: {' '.join(cmd[:6])}...")

    result = subprocess.run(cmd, cwd=str(Path(__file__).parent))

    if result.returncode == 0:
        print("\n" + "=" * 60)
        print("✅ 빌드 성공!")
        print(f"   📁 출력 경로: {dist_dir / '가족추억보관상자'}")
        print(f"   🚀 실행: {dist_dir / '가족추억보관상자' / '가족추억보관상자.exe'}")
        print("=" * 60)

        # web 폴더도 복사
        web_src = Path(__file__).parent / "web"
        web_dst = dist_dir / "가족추억보관상자" / "web"
        if web_src.exists():
            shutil.copytree(str(web_src), str(web_dst))
            print(f"   📂 웹 파일 복사됨: {web_dst}")

        # .env.example 복사
        env_src = server_dir / ".env.example"
        if env_src.exists():
            shutil.copy2(str(env_src),
                         str(dist_dir / "가족추억보관상자" / ".env.example"))
            print("   📝 .env.example 복사됨")

        # 간단한 실행 배치 파일 생성
        bat_path = dist_dir / "가족추억보관상자" / "실행.bat"
        bat_path.write_text(
            '@echo off\n'
            'echo ========================================\n'
            'echo   가족 추억 보관 상자 서버 시작 중...\n'
            'echo ========================================\n'
            'echo.\n'
            'echo 브라우저에서 http://localhost:8000 으로 접속하세요.\n'
            'echo 종료하려면 이 창을 닫으세요.\n'
            'echo.\n'
            '가족추억보관상자.exe\n',
            encoding='utf-8',
        )
        print("   📋 실행.bat 생성됨")

    else:
        print(f"\n❌ 빌드 실패 (코드: {result.returncode})")
        print("   PyInstaller 로그를 확인하세요.")
        sys.exit(1)


if __name__ == "__main__":
    build_exe()
