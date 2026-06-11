"""
전체 폴더 재지오코딩 — 개선된 Nominatim 필드로 폴더명 업그레이드
- 동네이름(신장동, 덕풍동 등)으로 된 폴더를 구체적 장소명으로 변경
- shop, railway, building 등 새로 추가된 필드 활용
"""

import os
import json
import sqlite3
import time
import re
from pathlib import Path
from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS
from geopy.geocoders import Nominatim

EXTERNAL_DRIVE = Path(r"D:\가족사진")
DB_PATH = Path.home() / "Desktop" / "사진모음집" / "data" / "photo_archive.db"

geo = Nominatim(user_agent="family-photo-archive/1.0")

# 동네/행정구역 이름 = 업그레이드 대상 (더 구체적인 이름으로 바꿀 수 있는 폴더)
# 이미 구체적인 이름(스타벅스, 이마트 등)은 건드리지 않음

# 일반명 블랙리스트 (이걸로 바꾸면 안 됨)
GENERIC_NAMES = {
    "잔디축구장", "축구장", "풋살장", "농구장", "테니스장",
    "보조경기장", "체육관", "운동장", "수영장", "배드민턴장",
    "주차장", "공영주차장", "놀이터", "어린이 놀이터",
    "화장실", "공중화장실", "정류장", "버스정류장",
    "벤치", "쉼터", "산책로", "자전거도로",
    "비상급수시설", "전기차충전소", "충전소",
    "보육시설", "유치원", "어린이집",
    "주민센터", "파출소", "우체국",
}

# 구체적 장소를 찾을 수 있는 Nominatim 필드
LANDMARK_FIELDS = [
    "leisure", "tourism", "amenity", "shop", "building",
    "historic", "railway", "aeroway", "office",
    "place_of_worship", "healthcare", "school", "stadium",
    "craft", "club",
]

# 동네/행정구역 필드 (현재 이 이름으로 되어있으면 업그레이드 시도)
NEIGHBOURHOOD_FIELDS = ["neighbourhood", "quarter", "suburb", "village", "town",
                        "city", "county", "city_district"]


def to_deg(v):
    return float(v[0]) + float(v[1]) / 60 + float(v[2]) / 3600


def get_gps_from_folder(folder: Path):
    """폴더 내 모든 사진의 GPS 수집"""
    coords = []
    for f in folder.iterdir():
        if f.suffix.lower() not in ('.jpg', '.jpeg', '.png'):
            continue
        try:
            img = Image.open(f)
            exif = img._getexif()
            if not exif:
                continue
            for tid, val in exif.items():
                if TAGS.get(tid) == "GPSInfo":
                    gd = {GPSTAGS.get(k, k): v for k, v in val.items()}
                    lat = to_deg(gd["GPSLatitude"])
                    lon = to_deg(gd["GPSLongitude"])
                    if lat != 0 and lon != 0:
                        coords.append((lat, lon))
                    break
        except Exception:
            continue
    return coords


def get_best_name(lat, lon):
    """GPS에서 가장 구체적인 장소명 추출 (개선된 로직)"""
    try:
        time.sleep(1.1)
        loc = geo.reverse(f"{lat}, {lon}", language="ko", exactly_one=True)
        if not loc:
            return None, None, None
        addr = loc.raw.get("address", {})
        
        # 구체적 장소명 검색
        for field in LANDMARK_FIELDS:
            name = addr.get(field)
            if name and name not in GENERIC_NAMES:
                house = addr.get("house_number", "")
                road = addr.get("road", "")
                addr_key = f"{house}_{road}" if house and road else None
                return name, field, addr_key
        
        return None, None, None
    except Exception:
        return None, None, None


def sanitize(name):
    forbidden = '<>:"/\\|?*'
    s = "".join(c if c not in forbidden else "_" for c in name)
    return re.sub(r"_+", "_", s).strip("_. ")[:50]


def is_neighbourhood_name(folder_name):
    """동네/행정구역 이름인지 판별 (한글 2~4글자 동/리/면/읍/구/시 등)"""
    # 한글 끝나는 패턴: ~동, ~리, ~면, ~읍, ~구, ~시, ~군
    if re.match(r'^.{1,10}(동|리|면|읍|구|시|군)$', folder_name):
        return True
    # 일본어 지명 (xx丁目 등)
    if re.search(r'[丁目町村]', folder_name):
        return True
    return False


def main():
    print("=" * 60)
    print("🔄 전체 폴더 재지오코딩")
    print("=" * 60)
    
    results = []
    skipped = 0
    
    for date_dir in sorted(EXTERNAL_DRIVE.iterdir()):
        if not date_dir.is_dir():
            continue
        
        for place_dir in sorted(date_dir.iterdir()):
            if not place_dir.is_dir() or place_dir.name == "위치미상":
                continue
            if place_dir.name.startswith("."):
                continue
            
            # 이미 구체적인 이름이면 건너뛰기
            if not is_neighbourhood_name(place_dir.name):
                skipped += 1
                continue
            
            # GPS 추출
            coords = get_gps_from_folder(place_dir)
            if not coords:
                continue
            
            # 각 사진의 GPS로 장소명 조회, 가장 좋은 이름 선택
            best_name = None
            best_field = None
            best_addr_key = None
            
            for lat, lon in coords[:3]:  # 최대 3장만 확인
                name, field, addr_key = get_best_name(lat, lon)
                if name:
                    best_name = name
                    best_field = field
                    best_addr_key = addr_key
                    break  # 하나라도 구체적 이름 찾으면 사용
            
            if not best_name:
                continue
            
            safe_name = sanitize(best_name)
            if safe_name == place_dir.name:
                continue
            
            new_folder = date_dir / safe_name
            file_count = len(list(place_dir.iterdir()))
            
            try:
                if new_folder.exists():
                    # 이미 같은 이름 폴더 존재 → 병합
                    for f in list(place_dir.iterdir()):
                        dest = new_folder / f.name
                        if not dest.exists():
                            os.rename(str(f), str(dest))
                    try:
                        place_dir.rmdir()
                    except OSError:
                        pass
                    print("  🔀 %s/%s → %s (병합, %d개)" % (date_dir.name, place_dir.name, safe_name, file_count))
                else:
                    os.rename(str(place_dir), str(new_folder))
                    print("  ✅ %s/%s → %s (%s, %d개)" % (date_dir.name, place_dir.name, safe_name, best_field, file_count))
                
                results.append((date_dir.name, place_dir.name, safe_name, best_field or "", file_count))
                
                # DB 업데이트
                _update_db(str(place_dir), str(new_folder))
                
                # address_keys 캐시 업데이트
                if best_addr_key:
                    cache_file = date_dir / ".address_keys.json"
                    cache = {}
                    if cache_file.exists():
                        try:
                            with open(cache_file, "r", encoding="utf-8") as f:
                                cache = json.load(f)
                        except:
                            pass
                    if place_dir.name in cache:
                        cache[safe_name] = cache.pop(place_dir.name)
                    else:
                        cache[safe_name] = best_addr_key
                    with open(cache_file, "w", encoding="utf-8") as f:
                        json.dump(cache, f, ensure_ascii=False, indent=2)
                
            except Exception as e:
                print("  ❌ %s/%s: %s" % (date_dir.name, place_dir.name, e))
    
    # 결과
    print("\n" + "=" * 60)
    if results:
        print("📊 재지오코딩 결과: %d개 폴더 업그레이드" % len(results))
        print("=" * 60)
        print("%-14s %-18s → %-22s %-8s %s" % ("날짜", "기존", "변경", "필드", "파일"))
        print("-" * 75)
        for date, old, new, field, cnt in results:
            print("%-14s %-18s → %-22s %-8s %d개" % (date, old, new, field, cnt))
    else:
        print("✅ 업그레이드할 폴더가 없습니다.")
    print("\n⏭️ 건너뜀 (이미 구체적 이름): %d개" % skipped)


def _update_db(old_folder, new_folder):
    if not DB_PATH.exists():
        return
    try:
        conn = sqlite3.connect(str(DB_PATH))
        for old_s, new_s in [(old_folder.replace("\\", "/"), new_folder.replace("\\", "/")),
                              (old_folder.replace("/", "\\"), new_folder.replace("/", "\\"))]:
            conn.execute(
                "UPDATE photos SET original_path = REPLACE(original_path, ?, ?) WHERE original_path LIKE ?",
                (old_s, new_s, old_s + "%")
            )
        conn.commit()
        conn.close()
    except Exception as e:
        print("  ⚠️ DB: %s" % e)


if __name__ == "__main__":
    main()
