"""
EXIF 메타데이터 추출 서비스
- Pillow + piexif로 EXIF 파싱
- GPS 좌표 추출 (위도/경도)
- 촬영 일시, 카메라 모델 추출
- Nominatim 역지오코딩 (GPS → 주소, 100% 무료)
"""

import io
from datetime import datetime
from PIL import Image, ExifTags
from PIL.ExifTags import TAGS, GPSTAGS
from geopy.geocoders import Nominatim
from geopy.adapters import AioHTTPAdapter
import asyncio

from config import settings


class ExifService:
    """EXIF 메타데이터 추출 및 지오코딩 서비스"""

    def __init__(self):
        self._geocoder = None

    async def _get_geocoder(self):
        """Nominatim 역지오코더 (비동기)"""
        if self._geocoder is None:
            self._geocoder = Nominatim(
                user_agent=settings.NOMINATIM_USER_AGENT,
                adapter_factory=AioHTTPAdapter,
            )
        return self._geocoder

    def extract_exif(self, image_bytes: bytes, filename: str = "") -> dict:
        """
        이미지 바이트에서 EXIF 데이터 추출
        동영상은 EXIF 추출 불가 → 파일명에서 날짜 추출 폴백

        Returns:
            {
                "taken_at": "2024-03-15 14:30:22",
                "latitude": 37.5665,
                "longitude": 126.9780,
                "camera_model": "Samsung SM-S918N",
                "orientation": 1,
                "has_gps": True
            }
        """
        result = {
            "taken_at": None,
            "latitude": None,
            "longitude": None,
            "camera_model": None,
            "orientation": 1,
            "has_gps": False,
        }

        try:
            img = Image.open(io.BytesIO(image_bytes))
            exif_data = img._getexif()

            if not exif_data:
                # EXIF 없으면 파일명에서 날짜 추출 시도
                result["taken_at"] = self._parse_date_from_filename(filename)
                return result

            # 태그별 데이터 추출
            for tag_id, value in exif_data.items():
                tag_name = TAGS.get(tag_id, tag_id)

                if tag_name == "DateTimeOriginal":
                    try:
                        result["taken_at"] = datetime.strptime(
                            str(value), "%Y:%m:%d %H:%M:%S"
                        ).isoformat()
                    except (ValueError, TypeError):
                        pass

                elif tag_name == "Model":
                    result["camera_model"] = str(value).strip()

                elif tag_name == "Orientation":
                    result["orientation"] = int(value)

                elif tag_name == "GPSInfo":
                    gps = self._parse_gps_info(value)
                    if gps:
                        result["latitude"] = gps["latitude"]
                        result["longitude"] = gps["longitude"]
                        result["has_gps"] = True

        except Exception as e:
            print(f"⚠️ EXIF 추출 실패: {e}")

        # EXIF에서 날짜를 못 찾았으면 파일명에서 추출
        if not result["taken_at"] and filename:
            result["taken_at"] = self._parse_date_from_filename(filename)

        return result

    @staticmethod
    def _parse_date_from_filename(filename: str) -> str | None:
        """
        파일명에서 날짜/시간 추출 (EXIF 없는 동영상 등에 사용)
        지원 패턴:
          - 20260530_133749.mp4 → 2026-05-30T13:37:49
          - IMG_20260530_133749.jpg → 2026-05-30T13:37:49
          - Screenshot_20260530_133749.jpg → 2026-05-30T13:37:49
          - VID_20260530_133749.mp4 → 2026-05-30T13:37:49
          - 2025_11_24 10_32.mp4 → 2025-11-24T10:32:00 (카카오톡 등)
          - 20260530.jpg → 2026-05-30T00:00:00
        """
        import re

        if not filename:
            return None

        # 패턴 1: YYYYMMDD_HHMMSS (가장 흔한 패턴)
        match = re.search(r'(\d{4})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])[\-_](\d{2})(\d{2})(\d{2})', filename)
        if match:
            try:
                dt = datetime(
                    int(match.group(1)), int(match.group(2)), int(match.group(3)),
                    int(match.group(4)), int(match.group(5)), int(match.group(6))
                )
                return dt.isoformat()
            except ValueError:
                pass

        # 패턴 2: YYYY_MM_DD HH_MM (카카오톡, 메신저 저장 파일)
        match = re.search(r'(\d{4})[_\-](0[1-9]|1[0-2])[_\-](0[1-9]|[12]\d|3[01])\s+(\d{2})[_\-](\d{2})', filename)
        if match:
            try:
                dt = datetime(
                    int(match.group(1)), int(match.group(2)), int(match.group(3)),
                    int(match.group(4)), int(match.group(5))
                )
                return dt.isoformat()
            except ValueError:
                pass

        # 패턴 3: YYYYMMDD만 (시간 없음)
        match = re.search(r'(\d{4})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])', filename)
        if match:
            try:
                dt = datetime(
                    int(match.group(1)), int(match.group(2)), int(match.group(3))
                )
                return dt.isoformat()
            except ValueError:
                pass

        return None

    def _parse_gps_info(self, gps_info: dict) -> dict | None:
        """GPS 태그 → 위도/경도 변환"""
        import math
        try:
            gps_data = {}
            for key, val in gps_info.items():
                tag_name = GPSTAGS.get(key, key)
                gps_data[tag_name] = val

            # 위도 계산
            lat = gps_data.get("GPSLatitude")
            lat_ref = gps_data.get("GPSLatitudeRef", "N")
            if lat:
                latitude = self._convert_to_degrees(lat)
                if math.isnan(latitude) or latitude == 0.0:
                    return None
                if lat_ref == "S":
                    latitude = -latitude
            else:
                return None

            # 경도 계산
            lon = gps_data.get("GPSLongitude")
            lon_ref = gps_data.get("GPSLongitudeRef", "E")
            if lon:
                longitude = self._convert_to_degrees(lon)
                if math.isnan(longitude) or longitude == 0.0:
                    return None
                if lon_ref == "W":
                    longitude = -longitude
            else:
                return None

            return {"latitude": latitude, "longitude": longitude}

        except Exception:
            return None

    @staticmethod
    def _convert_to_degrees(value) -> float:
        """
        GPS 좌표를 도(degree) 단위로 변환
        EXIF GPS 데이터는 (도, 분, 초) 형태의 튜플
        """
        try:
            d = float(value[0])
            m = float(value[1])
            s = float(value[2])
            return d + (m / 60.0) + (s / 3600.0)
        except (IndexError, TypeError, ValueError):
            return 0.0

    async def reverse_geocode(self, latitude: float, longitude: float) -> str | None:
        """
        GPS 좌표 → 주소 변환 (Nominatim, 100% 무료)
        - 속도 제한: 1초에 1요청 (정책 준수)
        """
        try:
            geocoder = await self._get_geocoder()

            # 속도 제한 준수
            await asyncio.sleep(settings.NOMINATIM_RATE_LIMIT)

            location = await geocoder.reverse(
                f"{latitude}, {longitude}",
                language="ko",  # 한국어 결과
                exactly_one=True,
            )

            if location:
                # 주소에서 의미 있는 장소명 추출
                address = location.raw.get("address", {})
                
                # 디버그: 전체 주소 출력
                print(f"🔍 Nominatim 주소: {address}")
                
                # 1순위: 구체적 장소명 (매장, 관광지, 시설 등)
                landmark = (
                    address.get("leisure")           # 공원, 놀이터
                    or address.get("tourism")        # 관광지, 테마파크
                    or address.get("amenity")        # 편의시설 (카페, 학교 등)
                    or address.get("shop")           # 쇼핑몰 (스타필드, 이마트)
                    or address.get("building")       # 건물명 (코엑스)
                    or address.get("historic")       # 유적지 (경복궁)
                    or address.get("railway")        # 역 (강남, 홍대입구)
                    or address.get("aeroway")        # 공항
                    or address.get("office")         # 사무실 건물
                    or address.get("place_of_worship")  # 사찰, 성당
                    or address.get("healthcare")     # 병원
                    or address.get("school")         # 학교
                    or address.get("stadium")        # 경기장
                    or address.get("craft")          # 공방, 작업장
                    or address.get("club")           # 클럽, 동호회
                )
                
                # 일반 시설명 필터: 어디에나 있는 이름은 무시 → 동네이름으로 대체
                _GENERIC_NAMES = {
                    "잔디축구장", "축구장", "풋살장", "농구장", "테니스장",
                    "보조경기장", "체육관", "운동장", "수영장", "배드민턴장",
                    "주차장", "공영주차장", "놀이터", "어린이 놀이터",
                    "화장실", "공중화장실", "정류장", "버스정류장",
                    "벤치", "쉼터", "산책로", "자전거도로",
                    "비상급수시설", "전기차충전소", "충전소",
                    "보육시설", "유치원", "어린이집",
                    "주민센터", "파출소", "우체국",
                }
                if landmark and landmark in _GENERIC_NAMES:
                    print(f"🔄 일반명 필터링: '{landmark}' → 동네이름으로 대체")
                    landmark = None
                
                # 2순위: 동네 이름
                neighbourhood = (
                    address.get("neighbourhood")     # 동네
                    or address.get("quarter")        # 지역구
                    or address.get("suburb")         # 행정동
                    or address.get("village")        # 마을 (시골)
                    or address.get("town")           # 읍면
                )
                
                # 3순위: 시/구/군
                city = (
                    address.get("city")
                    or address.get("county")
                )
                
                # 조합: 랜드마크 > 동네 > 시/구 > 도로명 순
                if landmark:
                    place_name = landmark
                elif neighbourhood:
                    place_name = neighbourhood
                elif city:
                    place_name = city
                else:
                    place_name = address.get("road") or location.address
                
                return place_name

        except Exception as e:
            print(f"⚠️ 역지오코딩 실패 ({latitude}, {longitude}): {e}")

        return None

    async def search_places(self, query: str, limit: int = 5) -> list[dict]:
        """
        장소 검색 (Nominatim, 100% 무료)
        - 앱의 장소 검색 기능에 사용
        """
        try:
            geocoder = await self._get_geocoder()
            await asyncio.sleep(settings.NOMINATIM_RATE_LIMIT)

            locations = await geocoder.geocode(
                query,
                language="ko",
                exactly_one=False,
                limit=limit,
                addressdetails=True,
            )

            if not locations:
                return []

            results = []
            for loc in locations:
                results.append({
                    "name": loc.raw.get("name", query),
                    "display_name": loc.address,
                    "latitude": float(loc.latitude),
                    "longitude": float(loc.longitude),
                    "osm_type": loc.raw.get("osm_type"),
                    "category": loc.raw.get("type"),
                })
            return results

        except Exception as e:
            print(f"⚠️ 장소 검색 실패 ({query}): {e}")
            return []


# 싱글톤 인스턴스
exif_service = ExifService()
