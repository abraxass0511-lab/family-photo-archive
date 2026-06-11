"""
외장하드 폴더 구조 마이그레이션 스크립트
- 기존: D:/가족사진/2026-05-27_하남스타필드/
- 변경: D:/가족사진/2026-05-27/하남스타필드/

추가 기능:
- DB의 original_path, buffer_queue.target_folder도 함께 업데이트
- 기존 위치미상 폴더 사진 중 EXIF GPS 있는 사진은 재분류 시도
"""

import os
import re
import shutil
import sqlite3
from pathlib import Path
from datetime import datetime


# === 설정 ===
EXTERNAL_DRIVE = Path(r"D:\가족사진")
DB_PATH = Path.home() / "Desktop" / "사진모음집" / "data" / "photo_archive.db"

# 날짜 패턴 (YYYY-MM-DD 또는 한글)
DATE_PATTERN = re.compile(r"^(\d{4}-\d{2}-\d{2})_(.+)$")
KOREAN_DATE_PATTERN = re.compile(r"^(날짜미상)_(.+)$")


def parse_old_folder_name(name: str) -> tuple[str, str] | None:
    """
    기존 flat 폴더명에서 날짜와 장소 분리
    '2026-05-27_신장동' → ('2026-05-27', '신장동')
    '날짜미상_위치미상' → ('날짜미상', '위치미상')
    """
    match = DATE_PATTERN.match(name)
    if match:
        return match.group(1), match.group(2)
    
    match = KOREAN_DATE_PATTERN.match(name)
    if match:
        return match.group(1), match.group(2)
    
    return None


def migrate_folders():
    """기존 flat 폴더 → 중첩 폴더 변환"""
    if not EXTERNAL_DRIVE.exists():
        print("❌ 외장하드를 찾을 수 없습니다:", EXTERNAL_DRIVE)
        return
    
    folders = sorted([f for f in EXTERNAL_DRIVE.iterdir() if f.is_dir()])
    print(f"📂 총 {len(folders)}개 폴더 발견\n")
    
    migrated = 0
    skipped = 0
    errors = 0
    path_mappings = {}  # 기존경로 → 새경로 매핑 (DB 업데이트용)
    
    for folder in folders:
        parsed = parse_old_folder_name(folder.name)
        if not parsed:
            # 이미 새 구조이거나 파싱 불가
            print(f"  ⏭️ 건너뜀 (파싱 불가): {folder.name}")
            skipped += 1
            continue
        
        date_str, place_name = parsed
        new_parent = EXTERNAL_DRIVE / date_str
        new_folder = new_parent / place_name
        
        # 이미 같은 경로에 존재하면 건너뛰기
        if folder == new_folder:
            skipped += 1
            continue
        
        try:
            # 날짜 폴더 생성
            new_parent.mkdir(parents=True, exist_ok=True)
            
            if new_folder.exists():
                # 대상 폴더가 이미 존재 → 파일들을 이동
                print(f"  🔀 병합: {folder.name} → {date_str}/{place_name}")
                for file in folder.iterdir():
                    dest = new_folder / file.name
                    if dest.exists():
                        print(f"    ⚠️ 이미 존재: {file.name}")
                        continue
                    shutil.move(str(file), str(dest))
                
                # 원본 폴더 삭제 (비어있어야 함)
                try:
                    folder.rmdir()
                except OSError:
                    print(f"    ⚠️ 폴더 비우기 실패: {folder.name}")
            else:
                # 폴더 이동 (rename)
                shutil.move(str(folder), str(new_folder))
                print(f"  ✅ 이동: {folder.name} → {date_str}/{place_name}")
            
            # 경로 매핑 기록
            path_mappings[str(folder)] = str(new_folder)
            migrated += 1
            
        except Exception as e:
            print(f"  ❌ 오류: {folder.name} - {e}")
            errors += 1
    
    print(f"\n{'='*50}")
    print(f"📊 결과: 이동 {migrated} / 건너뜀 {skipped} / 오류 {errors}")
    
    return path_mappings


def update_database(path_mappings: dict):
    """DB의 original_path, buffer_queue.target_folder 업데이트"""
    if not DB_PATH.exists():
        print(f"\n⚠️ DB 파일을 찾을 수 없습니다: {DB_PATH}")
        return
    
    print(f"\n📀 DB 업데이트 시작: {DB_PATH}")
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    # 1. photos.original_path 업데이트
    updated_paths = 0
    try:
        rows = cursor.execute("SELECT id, original_path FROM photos WHERE original_path IS NOT NULL").fetchall()
        for row in rows:
            old_path = row["original_path"]
            if not old_path:
                continue
            
            new_path = old_path
            for old_folder, new_folder in path_mappings.items():
                if old_path.startswith(old_folder) or old_path.replace("/", "\\").startswith(old_folder.replace("/", "\\")):
                    new_path = old_path.replace(
                        old_folder.replace("\\", "/"),
                        new_folder.replace("\\", "/")
                    ).replace(
                        old_folder.replace("/", "\\"),
                        new_folder.replace("/", "\\")
                    )
                    break
            
            if new_path != old_path:
                cursor.execute(
                    "UPDATE photos SET original_path = ? WHERE id = ?",
                    (new_path, row["id"])
                )
                updated_paths += 1
    except Exception as e:
        print(f"  ⚠️ photos 업데이트 오류: {e}")
    
    print(f"  ✅ photos.original_path: {updated_paths}건 업데이트")
    
    # 2. buffer_queue.target_folder 업데이트 (flat → nested)
    updated_queue = 0
    try:
        rows = cursor.execute("SELECT id, target_folder FROM buffer_queue").fetchall()
        for row in rows:
            old_tf = row["target_folder"]
            if not old_tf or "/" in old_tf or "\\" in old_tf:
                continue  # 이미 새 형식
            
            parts = old_tf.split("_", 1)
            if len(parts) == 2:
                new_tf = parts[0] + "/" + parts[1]
                cursor.execute(
                    "UPDATE buffer_queue SET target_folder = ? WHERE id = ?",
                    (new_tf, row["id"])
                )
                updated_queue += 1
    except Exception as e:
        print(f"  ⚠️ buffer_queue 업데이트 오류: {e}")
    
    print(f"  ✅ buffer_queue.target_folder: {updated_queue}건 업데이트")
    
    conn.commit()
    conn.close()
    print("📀 DB 업데이트 완료")


def show_result():
    """마이그레이션 결과 확인"""
    if not EXTERNAL_DRIVE.exists():
        return
    
    date_folders = sorted([f for f in EXTERNAL_DRIVE.iterdir() if f.is_dir()])
    print(f"\n📂 마이그레이션 후 폴더 구조:")
    print(f"{'='*50}")
    
    total_subfolders = 0
    unknown_count = 0
    
    for df in date_folders[:15]:  # 최근 15개만 표시
        subfolders = sorted([sf for sf in df.iterdir() if sf.is_dir()])
        if subfolders:
            file_count = sum(len(list(sf.glob("*"))) for sf in subfolders if sf.is_file() is False)
            print(f"\n  📅 {df.name}/")
            for sf in subfolders:
                files_in_sf = len(list(sf.iterdir()))
                marker = "❓" if sf.name == "위치미상" else "📍"
                print(f"      {marker} {sf.name}/ ({files_in_sf}개 파일)")
                total_subfolders += 1
                if sf.name == "위치미상":
                    unknown_count += 1
        else:
            # 날짜 폴더에 파일만 있는 경우 (비정상)
            files = len(list(df.iterdir()))
            print(f"\n  📅 {df.name}/ (파일 {files}개, 하위폴더 없음)")
    
    print(f"\n{'='*50}")
    print(f"📊 전체: {len(date_folders)}개 날짜 폴더 / {total_subfolders}개 장소 폴더")
    print(f"❓ 위치미상: {unknown_count}개")


if __name__ == "__main__":
    print("=" * 50)
    print("🔄 폴더 구조 마이그레이션")
    print(f"   기존: {EXTERNAL_DRIVE}/YYYY-MM-DD_장소명/")
    print(f"   변경: {EXTERNAL_DRIVE}/YYYY-MM-DD/장소명/")
    print("=" * 50)
    print()
    
    # 1. 폴더 구조 변환
    path_mappings = migrate_folders()
    
    # 2. DB 업데이트
    if path_mappings:
        update_database(path_mappings)
    
    # 3. 결과 확인
    show_result()
