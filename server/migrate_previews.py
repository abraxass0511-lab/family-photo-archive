"""
기존 동영상 미리보기 일괄 생성 마이그레이션 스크립트
- 외장하드 연결 필요 (original_path에서 직접 읽음)
- FFmpeg 필요
"""

import sqlite3
from pathlib import Path
from services.preview_service import preview_service


def migrate():
    if not preview_service.is_available:
        print("❌ FFmpeg이 설치되지 않았습니다. 설치 후 다시 실행하세요.")
        return

    db_path = Path.home() / "Desktop" / "사진모음집" / "data" / "photo_archive.db"
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # preview_path 컬럼 추가 (없으면)
    try:
        c.execute("ALTER TABLE photos ADD COLUMN preview_path TEXT")
        conn.commit()
        print("📦 preview_path 컬럼 추가")
    except Exception:
        pass

    # 동영상 중 미리보기 없는 것 조회
    c.execute("""
        SELECT id, filename, buffer_path, original_path 
        FROM photos 
        WHERE (filename LIKE '%.mp4' OR filename LIKE '%.mov' OR filename LIKE '%.3gp')
        AND (preview_path IS NULL OR preview_path = '')
    """)
    videos = c.fetchall()

    print(f"\n🎬 미리보기 생성 대상: {len(videos)}개 동영상")
    
    success = 0
    fail = 0
    
    for i, v in enumerate(videos, 1):
        print(f"\n[{i}/{len(videos)}] {v['filename']}")
        
        # 파일 경로 탐색
        video_path = None
        for col in ['buffer_path', 'original_path']:
            if v[col]:
                p = Path(v[col])
                if p.exists():
                    video_path = p
                    break
        
        if not video_path:
            print(f"  ⚠️ 파일 찾을 수 없음 (외장하드 연결 확인)")
            fail += 1
            continue
        
        # 미리보기 생성 (파일 경로에서 직접)
        preview_path = preview_service.create_preview_from_file(video_path, v['id'])
        
        if preview_path:
            c.execute(
                "UPDATE photos SET preview_path = ? WHERE id = ?",
                (preview_path, v['id'])
            )
            conn.commit()
            success += 1
        else:
            fail += 1
    
    print(f"\n{'='*40}")
    print(f"✅ 완료: {success}개 성공, {fail}개 실패")
    print(f"{'='*40}")
    
    conn.close()


if __name__ == "__main__":
    migrate()
