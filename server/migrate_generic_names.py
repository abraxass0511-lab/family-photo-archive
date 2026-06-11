"""
일반 시설명 필터링 + 폴더 재분류 스크립트
- "잔디축구장", "보조경기장" 등 일반명 → 동네이름으로 변경
- EXIF GPS로 재지오코딩하여 동네이름 획득
"""

import re
import shutil
import sqlite3
import time
from pathlib import Path
from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS
from geopy.geocoders import Nominatim

# === 설정 ===
EXTERNAL_DRIVE = Path(r"D:\가족사진")
DB_PATH = Path.home() / "Desktop" / "사진모음집" / "data" / "photo_archive.db"

# 일반 시설명 블랙리스트 (어디에나 있는 시설)
GENERIC_PLACE_NAMES = {
    # 운동/체육 시설
    "잔디축구장", "축구장", "풋살장", "농구장", "테니스장",
    "보조경기장", "체육관", "운동장", "수영장",
    # 편의/공공 시설  
    "주차장", "놀이터", "어린이 놀이터", "화장실", "공중화장실",
    "정류장", "버스정류장", "벤치", "쉼터", "산책로",
    "비상급수시설", "전기차충전소",
    # 보육/교육 일반명
    "보육시설", "유치원", "어린이집",
}

geo = Nominatim(user_agent="family-photo-archive/1.0")


def convert_to_degrees(value):
    d = float(value[0])
    m = float(value[1])
    s = float(value[2])
    return d + (m / 60.0) + (s / 3600.0)


def get_gps_from_folder(folder: Path) -> tuple[float, float] | None:
    """폴더 내 사진에서 GPS 좌표 추출 (첫 번째 발견된 것 사용)"""
    for f in folder.iterdir():
        if f.suffix.lower() not in ('.jpg', '.jpeg', '.png'):
            continue
        try:
            img = Image.open(f)
            exif = img._getexif()
            if not exif:
                continue
            for tag_id, value in exif.items():
                if TAGS.get(tag_id) == "GPSInfo":
                    gps_data = {}
                    for key, val in value.items():
                        gps_data[GPSTAGS.get(key, key)] = val
                    lat = convert_to_degrees(gps_data["GPSLatitude"])
                    if gps_data.get("GPSLatitudeRef") == "S":
                        lat = -lat
                    lon = convert_to_degrees(gps_data["GPSLongitude"])
                    if gps_data.get("GPSLongitudeRef") == "W":
                        lon = -lon
                    if lat != 0 and lon != 0:
                        return (lat, lon)
        except Exception:
            continue
    return None


def get_neighbourhood_name(lat: float, lon: float) -> str | None:
    """GPS 좌표에서 동네이름 가져오기 (Nominatim)"""
    try:
        time.sleep(1.1)  # 속도 제한
        loc = geo.reverse(f"{lat}, {lon}", language="ko", exactly_one=True)
        if not loc:
            return None
        addr = loc.raw.get("address", {})
        # 동네 우선순위
        return (
            addr.get("neighbourhood")
            or addr.get("quarter")
            or addr.get("suburb")
            or addr.get("village")
            or addr.get("town")
            or addr.get("city")
            or addr.get("county")
        )
    except Exception as e:
        print(f"  ⚠️ 지오코딩 오류: {e}")
        return None


def sanitize_folder_name(name: str) -> str:
    """폴더명 안전하게 정리"""
    forbidden = '<>:"/\\|?*'
    sanitized = "".join(c if c not in forbidden else "_" for c in name)
    sanitized = re.sub(r"_+", "_", sanitized).strip("_. ")
    return sanitized[:50]


def main():
    print("=" * 60)
    print("🔄 일반 시설명 → 동네이름 재분류")
    print("=" * 60)
    
    # 1. 재분류 대상 찾기
    targets = []
    for date_dir in sorted(EXTERNAL_DRIVE.iterdir()):
        if not date_dir.is_dir():
            continue
        for place_dir in date_dir.iterdir():
            if place_dir.is_dir() and place_dir.name in GENERIC_PLACE_NAMES:
                targets.append(place_dir)
    
    print(f"\n📋 재분류 대상: {len(targets)}개 폴더")
    for t in targets:
        files = len(list(t.iterdir()))
        print(f"  ❌ {t.parent.name}/{t.name} ({files}개 파일)")
    
    if not targets:
        print("\n✅ 재분류할 폴더가 없습니다.")
        return
    
    # 2. 재분류 실행
    print(f"\n{'='*60}")
    print("🔄 재분류 시작...")
    
    results = []  # (날짜, 기존이름, 새이름, 파일수)
    
    for place_dir in targets:
        date_name = place_dir.parent.name
        old_name = place_dir.name
        file_count = len(list(place_dir.iterdir()))
        
        # GPS 추출
        gps = get_gps_from_folder(place_dir)
        if not gps:
            print(f"  ⏭️ GPS 없음: {date_name}/{old_name}")
            results.append((date_name, old_name, old_name + " (GPS없음)", file_count))
            continue
        
        # 동네이름 가져오기
        new_name = get_neighbourhood_name(gps[0], gps[1])
        if not new_name:
            print(f"  ⏭️ 동네이름 없음: {date_name}/{old_name}")
            results.append((date_name, old_name, old_name + " (동네명없음)", file_count))
            continue
        
        new_name = sanitize_folder_name(new_name)
        new_folder = place_dir.parent / new_name
        
        if new_folder == place_dir:
            results.append((date_name, old_name, new_name + " (동일)", file_count))
            continue
        
        try:
            if new_folder.exists():
                # 이미 같은 동네 폴더 존재 → 파일 병합
                print(f"  🔀 병합: {date_name}/{old_name} → {new_name}")
                for f in place_dir.iterdir():
                    dest = new_folder / f.name
                    if not dest.exists():
                        shutil.move(str(f), str(dest))
                try:
                    place_dir.rmdir()
                except OSError:
                    pass
            else:
                # 폴더 이름 변경
                shutil.move(str(place_dir), str(new_folder))
                print(f"  ✅ 변경: {date_name}/{old_name} → {new_name}")
            
            results.append((date_name, old_name, new_name, file_count))
            
            # DB 업데이트
            _update_db_paths(str(place_dir), str(new_folder))
            
        except Exception as e:
            print(f"  ❌ 오류: {date_name}/{old_name} - {e}")
            results.append((date_name, old_name, f"오류: {e}", file_count))
    
    # 3. 결과 요약
    print(f"\n{'='*60}")
    print("📊 재분류 결과")
    print(f"{'='*60}")
    print(f"{'날짜':<14} {'기존 이름':<20} {'새 이름':<20} {'파일수':>5}")
    print("-" * 60)
    for date, old, new, cnt in results:
        changed = "→" if old != new and "오류" not in new and "없음" not in new and "동일" not in new else "  "
        print(f"{date:<14} {old:<20} {changed} {new:<20} {cnt:>3}개")


def _update_db_paths(old_folder: str, new_folder: str):
    """DB 경로 업데이트"""
    if not DB_PATH.exists():
        return
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cursor = conn.cursor()
        
        # photos.original_path 업데이트
        old_prefix = old_folder.replace("\\", "/")
        new_prefix = new_folder.replace("\\", "/")
        cursor.execute(
            "UPDATE photos SET original_path = REPLACE(original_path, ?, ?) WHERE original_path LIKE ?",
            (old_prefix, new_prefix, old_prefix + "%")
        )
        
        # Windows 경로도 처리
        old_win = old_folder.replace("/", "\\")
        new_win = new_folder.replace("/", "\\")
        cursor.execute(
            "UPDATE photos SET original_path = REPLACE(original_path, ?, ?) WHERE original_path LIKE ?",
            (old_win, new_win, old_win + "%")
        )
        
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"  ⚠️ DB 업데이트 오류: {e}")


if __name__ == "__main__":
    main()
