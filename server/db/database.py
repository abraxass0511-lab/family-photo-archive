"""
데이터베이스 관리 모듈
- SQLite 비동기 연결 (aiosqlite)
- 사진, 인물, 장소, 사용자 테이블 스키마
- 자동 마이그레이션
"""

import aiosqlite
from pathlib import Path
from config import settings


# === 스키마 정의 ===
SCHEMA_SQL = """
-- ============================================
-- 사용자 관리 테이블 (보안: bcrypt 해싱)
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,               -- 표시 이름 (예: "아빠", "엄마")
    password_hash TEXT NOT NULL,              -- bcrypt 해시 (단방향, 복호화 불가)
    role TEXT NOT NULL DEFAULT 'member',      -- 'admin' 또는 'member'
    is_active INTEGER NOT NULL DEFAULT 1,     -- 계정 활성화 여부
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 사진 테이블
-- ============================================
CREATE TABLE IF NOT EXISTS photos (
    id TEXT PRIMARY KEY,                      -- 파일 SHA-256 해시 (중복 방지)
    filename TEXT NOT NULL,                   -- 원본 파일명
    taken_at TIMESTAMP,                       -- 촬영 일시 (EXIF)
    latitude REAL,                            -- GPS 위도
    longitude REAL,                           -- GPS 경도
    place_name TEXT,                          -- 장소명 (수동 매칭 또는 역지오코딩)
    is_backed_up INTEGER NOT NULL DEFAULT 0,  -- 외장하드 전송 완료 여부
    is_favorite INTEGER NOT NULL DEFAULT 0,   -- 하트(즐겨찾기)
    thumbnail_path TEXT,                      -- 썸네일 파일 경로
    original_path TEXT,                       -- 외장하드 내 원본 경로
    buffer_path TEXT,                         -- 임시 버퍼 경로 (이관 전)
    file_size INTEGER,                        -- 원본 파일 크기 (bytes)
    camera_model TEXT,                        -- 카메라/폰 모델
    uploaded_by INTEGER REFERENCES users(id), -- 업로드한 사용자
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 인물(가족) 테이블
-- ============================================
CREATE TABLE IF NOT EXISTS persons (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,                       -- 인물 이름 (예: "아들", "딸")
    face_encoding BLOB,                       -- 128차원 얼굴 벡터 (face_recognition)
    sample_thumbnail TEXT,                    -- 대표 얼굴 썸네일 경로
    photo_count INTEGER NOT NULL DEFAULT 0,   -- 등장 사진 수
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 사진-인물 연결 테이블 (N:N 관계)
-- ============================================
CREATE TABLE IF NOT EXISTS photo_persons (
    photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
    person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    confidence REAL DEFAULT 1.0,              -- 인식 신뢰도 (0.0~1.0)
    PRIMARY KEY (photo_id, person_id)
);

-- ============================================
-- 장소 테이블
-- ============================================
CREATE TABLE IF NOT EXISTS places (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,                       -- 장소명 (예: "하남스타필드 OO맛집")
    address TEXT,                             -- 주소
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    category TEXT,                            -- 장소 카테고리 (식당, 카페, 공원 등)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 사진-장소 연결 테이블
-- ============================================
CREATE TABLE IF NOT EXISTS photo_places (
    photo_id TEXT PRIMARY KEY REFERENCES photos(id) ON DELETE CASCADE,
    place_id INTEGER NOT NULL REFERENCES places(id) ON DELETE CASCADE
);

-- ============================================
-- 버퍼 큐 테이블 (임시 저장소 → 외장하드 이관 추적)
-- ============================================
CREATE TABLE IF NOT EXISTS buffer_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    photo_id TEXT NOT NULL REFERENCES photos(id),
    buffer_file_path TEXT NOT NULL,           -- 임시 저장 경로
    target_folder TEXT NOT NULL,              -- 외장하드 대상 폴더명
    status TEXT NOT NULL DEFAULT 'pending',   -- pending / transferring / done / failed
    retry_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    transferred_at TIMESTAMP
);



-- 인덱스 (검색 성능 최적화)
CREATE INDEX IF NOT EXISTS idx_photos_taken_at ON photos(taken_at);
CREATE INDEX IF NOT EXISTS idx_photos_location ON photos(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_photos_backed_up ON photos(is_backed_up);
CREATE INDEX IF NOT EXISTS idx_photos_favorite ON photos(is_favorite);
CREATE INDEX IF NOT EXISTS idx_buffer_status ON buffer_queue(status);
CREATE INDEX IF NOT EXISTS idx_persons_name ON persons(name);
"""


class Database:
    """비동기 SQLite 데이터베이스 매니저"""

    def __init__(self):
        self.db_path = settings.db_path
        self._connection: aiosqlite.Connection | None = None

    async def connect(self):
        """DB 연결 및 초기화"""
        # 디렉토리 생성
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        self._connection = await aiosqlite.connect(str(self.db_path))
        # WAL 모드 활성화 (동시 읽기/쓰기 성능 향상)
        await self._connection.execute("PRAGMA journal_mode=WAL")
        # 외래 키 제약 활성화
        await self._connection.execute("PRAGMA foreign_keys=ON")
        # 스키마 생성
        await self._connection.executescript(SCHEMA_SQL)
        await self._connection.commit()
        print(f"✅ DB 연결 완료: {self.db_path}")

    async def disconnect(self):
        """DB 연결 종료"""
        if self._connection:
            await self._connection.close()
            self._connection = None
            print("🔌 DB 연결 종료")

    @property
    def conn(self) -> aiosqlite.Connection:
        """현재 DB 연결 반환"""
        if not self._connection:
            raise RuntimeError("DB가 연결되지 않았습니다. connect()를 먼저 호출하세요.")
        return self._connection

    async def execute(self, query: str, params: tuple = ()):
        """단일 쿼리 실행"""
        cursor = await self.conn.execute(query, params)
        await self.conn.commit()
        return cursor

    async def fetch_one(self, query: str, params: tuple = ()):
        """단일 행 조회"""
        self.conn.row_factory = aiosqlite.Row
        cursor = await self.conn.execute(query, params)
        return await cursor.fetchone()

    async def fetch_all(self, query: str, params: tuple = ()):
        """모든 행 조회"""
        self.conn.row_factory = aiosqlite.Row
        cursor = await self.conn.execute(query, params)
        return await cursor.fetchall()


# 싱글톤 DB 인스턴스
db = Database()
