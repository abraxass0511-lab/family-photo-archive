"""
같은 건물(번지+도로) 폴더 병합 마이그레이션
- 같은 날짜 폴더 내에서 GPS가 같은 주소(번지+도로)인 폴더들을 병합
- 예: Nike, 올리브영 → 스타필드 하남 (같은 주소 750_미사대로)
"""

import json
import re
import shutil
import sqlite3
import time
from pathlib import Path
from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS
from geopy.geocoders import Nominatim

EXTERNAL_DRIVE = Path(r"D:\가족사진")
DB_PATH = Path.home() / "Desktop" / "사진모음집" / "data" / "photo_archive.db"

geo = Nominatim(user_agent="family-photo-archive/1.0")


def to_deg(v):
    return float(v[0]) + float(v[1]) / 60 + float(v[2]) / 3600


def get_gps_from_folder(folder: Path) -> tuple[float, float] | None:
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
                    gd = {}
                    for k, v in val.items():
                        gd[GPSTAGS.get(k, k)] = v
                    lat = to_deg(gd["GPSLatitude"])
                    lon = to_deg(gd["GPSLongitude"])
                    if lat != 0 and lon != 0:
                        return (lat, lon)
        except Exception:
            continue
    return None


def get_address_info(lat: float, lon: float) -> dict | None:
    """Nominatim에서 주소 정보 가져오기"""
    try:
        time.sleep(1.1)
        loc = geo.reverse(f"{lat}, {lon}", language="ko", exactly_one=True)
        if loc:
            return loc.raw.get("address", {})
    except Exception:
        pass
    return None


def main():
    print("=" * 60)
    print("🏢 같은 건물 폴더 병합")
    print("=" * 60)
    
    results = []
    
    for date_dir in sorted(EXTERNAL_DRIVE.iterdir()):
        if not date_dir.is_dir():
            continue
        
        subfolders = [sf for sf in date_dir.iterdir() if sf.is_dir() and sf.name != "위치미상"]
        if len(subfolders) < 2:
            continue
        
        # 각 폴더의 GPS 좌표 + 주소 수집
        folder_info = {}
        for sf in subfolders:
            gps = get_gps_from_folder(sf)
            if gps:
                addr = get_address_info(gps[0], gps[1])
                if addr:
                    house = addr.get("house_number", "")
                    road = addr.get("road", "")
                    addr_key = f"{house}_{road}" if house and road else None
                    folder_info[sf.name] = {
                        "path": sf,
                        "gps": gps,
                        "addr_key": addr_key,
                        "addr": addr,
                        "files": len(list(sf.iterdir())),
                    }
        
        # 같은 addr_key끼리 그룹핑
        groups = {}
        for name, info in folder_info.items():
            key = info["addr_key"]
            if key:
                groups.setdefault(key, []).append((name, info))
        
        # 2개 이상 폴더가 같은 addr_key를 가진 경우 → 병합
        for addr_key, members in groups.items():
            if len(members) < 2:
                continue
            
            # 대표 폴더 선택: 구체적 장소명(shop/tourism/amenity) 우선, 같으면 파일 많은 순
            LANDMARK_FIELDS = {"shop", "tourism", "amenity", "leisure", "building", 
                              "historic", "railway", "aeroway", "healthcare", "school"}
            
            def _name_priority(item):
                name, info = item
                addr = info["addr"]
                # 구체적 장소명이 있으면 높은 우선순위 (1), 없으면 낮은 우선순위 (0)
                has_landmark = any(addr.get(f) for f in LANDMARK_FIELDS)
                return (1 if has_landmark else 0, info["files"])
            
            members.sort(key=_name_priority, reverse=True)
            main_name, main_info = members[0]
            main_folder = main_info["path"]
            
            print(f"\n📅 {date_dir.name}/ 주소: {addr_key}")
            print(f"  ✅ 대표: {main_name}/ ({main_info['files']}개)")
            
            for other_name, other_info in members[1:]:
                other_folder = other_info["path"]
                file_count = other_info["files"]
                
                # 파일 이동
                moved = 0
                for f in other_folder.iterdir():
                    dest = main_folder / f.name
                    if not dest.exists():
                        shutil.move(str(f), str(dest))
                        moved += 1
                    else:
                        print(f"    ⚠️ 중복: {f.name}")
                
                # 빈 폴더 삭제
                try:
                    other_folder.rmdir()
                except OSError:
                    pass
                
                # DB 업데이트
                _update_db(str(other_folder), str(main_folder))
                
                print(f"  🔀 병합: {other_name}/ ({file_count}개) → {main_name}/")
                results.append((date_dir.name, other_name, main_name, moved))
        
        # address_keys.json 캐시 생성
        cache = {}
        for name, info in folder_info.items():
            if info["addr_key"] and (date_dir / name).exists():
                cache[name] = info["addr_key"]
        if cache:
            cache_file = date_dir / ".address_keys.json"
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(cache, f, ensure_ascii=False, indent=2)
    
    # 결과 출력
    if results:
        print(f"\n{'='*60}")
        print("📊 병합 결과")
        print(f"{'='*60}")
        print(f"{'날짜':<14} {'기존 폴더':<25} {'→ 대표 폴더':<25} {'이동':>4}")
        print("-" * 70)
        for date, old, new, cnt in results:
            print(f"{date:<14} {old:<25} → {new:<25} {cnt:>3}개")
        print(f"\n총 {len(results)}개 폴더 병합 완료")
    else:
        print("\n✅ 병합할 폴더가 없습니다.")


def _update_db(old_folder: str, new_folder: str):
    if not DB_PATH.exists():
        return
    try:
        conn = sqlite3.connect(str(DB_PATH))
        old_fwd = old_folder.replace("\\", "/")
        new_fwd = new_folder.replace("\\", "/")
        conn.execute(
            "UPDATE photos SET original_path = REPLACE(original_path, ?, ?) WHERE original_path LIKE ?",
            (old_fwd, new_fwd, old_fwd + "%")
        )
        old_bk = old_folder.replace("/", "\\")
        new_bk = new_folder.replace("/", "\\")
        conn.execute(
            "UPDATE photos SET original_path = REPLACE(original_path, ?, ?) WHERE original_path LIKE ?",
            (old_bk, new_bk, old_bk + "%")
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"  ⚠️ DB 오류: {e}")


if __name__ == "__main__":
    main()
