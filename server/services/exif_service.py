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

    def extract_exif(self, image_bytes: bytes) -> dict:
        """
        이미지 바이트에서 EXIF 데이터 추출

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

        return result

    def _parse_gps_info(self, gps_info: dict) -> dict | None:
        """GPS 태그 → 위도/경도 변환"""
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
                if lat_ref == "S":
                    latitude = -latitude
            else:
                return None

            # 경도 계산
            lon = gps_data.get("GPSLongitude")
            lon_ref = gps_data.get("GPSLongitudeRef", "E")
            if lon:
                longitude = self._convert_to_degrees(lon)
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
                # 주소에서 간결한 장소명 추출
                address = location.raw.get("address", {})
                place_name = (
                    address.get("amenity")
                    or address.get("building")
                    or address.get("road")
                    or address.get("suburb")
                    or address.get("city")
                    or location.address
                )
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
