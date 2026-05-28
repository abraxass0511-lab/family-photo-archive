"""
가족 추억 보관 상자 — FastAPI 메인 서버

클라우드 제로 기반 가족 사진 아카이브 시스템
- 사진 업로드 → EXIF 추출 → 썸네일 → 얼굴 인식 → 저장
- 외장하드 자동 감지 + 임시 버퍼 관리
- 사용자 인증 (bcrypt + JWT)
- OpenStreetMap/Nominatim 기반 (100% 무료)
"""

import sys
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import settings
from db.database import db
from services.auth_service import ensure_admin_exists
from services.face_service import face_service
from utils.drive_watcher import drive_watcher

# 라우터 임포트
from routers.auth import router as auth_router
from routers.upload import router as upload_router
from routers.sync import router as sync_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """서버 시작/종료 생명주기 관리"""
    # === 서버 시작 ===
    print("=" * 50)
    print(f"🏠 {settings.APP_NAME} 서버 시작")
    print("=" * 50)

    # 디렉토리 생성
    settings.ensure_dirs()
    print("📁 데이터 디렉토리 준비 완료")

    # DB 연결 및 초기화
    await db.connect()

    # 기본 관리자 계정 확인/생성
    await ensure_admin_exists()

    # 얼굴 인식 데이터 로드
    await face_service.load_known_faces()

    # 외장하드 감지 워처 시작
    await drive_watcher.start()

    print("=" * 50)
    print(f"🚀 서버 준비 완료: http://{settings.HOST}:{settings.PORT}")
    print(f"📖 API 문서: http://localhost:{settings.PORT}/docs")
    print(f"💾 외장하드: {settings.EXTERNAL_DRIVE_PATH}")
    print(f"📦 버퍼: {settings.TEMP_BUFFER_PATH}")
    print("=" * 50)

    yield

    # === 서버 종료 ===
    await drive_watcher.stop()
    await db.disconnect()
    print("👋 서버 종료 완료")


# === FastAPI 앱 생성 ===
app = FastAPI(
    title=settings.APP_NAME,
    description="클라우드 제로 기반 가족 사진 아카이브 시스템",
    version="1.0.0",
    lifespan=lifespan,
)

# === CORS 미들웨어 (Flutter 앱 접근 허용) ===
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS + ["*"],  # 개발 단계에서는 모든 origin 허용
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# === 보안 미들웨어: Content Security Policy ===
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    """보안 헤더 추가"""
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response


# === 전역 예외 핸들러 ===
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """예상치 못한 오류 처리"""
    print(f"❌ 서버 오류: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "서버 내부 오류가 발생했습니다. 관리자에게 문의하세요."},
    )


# === 라우터 등록 ===
app.include_router(auth_router)
app.include_router(upload_router)
app.include_router(sync_router)


# === 헬스체크 ===
@app.get("/", tags=["시스템"])
async def root():
    """서버 상태 확인"""
    return {
        "name": settings.APP_NAME,
        "version": "1.0.0",
        "status": "running",
        "docs": f"http://localhost:{settings.PORT}/docs",
    }


@app.get("/health", tags=["시스템"])
async def health_check():
    """상세 헬스체크"""
    from services.storage_service import storage_service
    from services.buffer_service import buffer_service

    return {
        "status": "healthy",
        "database": "connected",
        "external_drive": storage_service.is_drive_connected(),
        "external_drive_path": settings.EXTERNAL_DRIVE_PATH,
        "buffer_pending": await buffer_service.get_pending_count(),
    }


# === 서버 실행 ===
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )
