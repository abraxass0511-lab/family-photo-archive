"""
카카오 로컬 API 서비스 (100% 무료, 일 10만 건)
- 키워드로 장소 검색 (한국 상호명 최적화)
- Nominatim 결과와 병합 (융합 검색)
- 디바운싱 + 일일 호출 카운터
"""

import asyncio
from datetime import date
from config import settings
from db.database import db

# aiohttp는 선택적 — 없으면 동기 방식 fallback
try:
    import aiohttp
    AIOHTTP_AVAILABLE = True
except ImportError:
    AIOHTTP_AVAILABLE = False

# Kakao REST API 키 (무료 발급: https://developers.kakao.com)
# .env 파일에 KAKAO_REST_API_KEY=your_key 형태로 설정
KAKAO_API_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"


class KakaoLocalService:
    """카카오 로컬 API 기반 장소 검색"""

    def __init__(self):
        self.api_key = getattr(settings, 'KAKAO_REST_API_KEY', '')
        self.daily_limit = 90000  # 10만 중 9만으로 안전 마진

    @property
    def is_available(self) -> bool:
        """API 키 설정 여부"""
        return bool(self.api_key)

    async def _check_daily_quota(self) -> bool:
        """일일 호출 횟수 확인 (비용 방어)"""
        today = date.today().isoformat()
        row = await db.fetch_one(
            "SELECT call_count FROM api_counters WHERE date = ? AND api_name = 'kakao_local'",
            (today,)
        )
        current = row["call_count"] if row else 0
        return current < self.daily_limit

    async def _increment_counter(self):
        """호출 카운터 증가"""
        today = date.today().isoformat()
        await db.execute(
            """INSERT INTO api_counters (date, api_name, call_count)
               VALUES (?, 'kakao_local', 1)
               ON CONFLICT(date, api_name) DO UPDATE SET call_count = call_count + 1""",
            (today,)
        )

    async def search_places(self, query: str, limit: int = 5) -> list[dict]:
        """
        카카오 키워드로 장소 검색

        Args:
            query: 검색어 (예: "OO돈까스 하남점")
            limit: 결과 수 (최대 15)

        Returns:
            [{"name": "OO돈까스 하남점", "address": "경기도 하남시...",
              "latitude": 37.55, "longitude": 127.21, "category": "음식점"}]
        """
        if not self.is_available:
            return []

        if not await self._check_daily_quota():
            print("⚠️ 카카오 API 일일 할당량 도달. Nominatim으로 대체합니다.")
            return []

        if not AIOHTTP_AVAILABLE:
            return await self._search_sync(query, limit)

        try:
            headers = {"Authorization": f"KakaoAK {self.api_key}"}
            params = {
                "query": query,
                "size": min(limit, 15),
                "sort": "accuracy",  # 정확도순
            }

            async with aiohttp.ClientSession() as session:
                async with session.get(KAKAO_API_URL, headers=headers, params=params) as resp:
                    if resp.status != 200:
                        error_text = await resp.text()
                        print(f"⚠️ 카카오 API 오류 ({resp.status}): {error_text}")
                        return []

                    data = await resp.json()

            await self._increment_counter()

            results = []
            for doc in data.get("documents", []):
                results.append({
                    "name": doc.get("place_name", query),
                    "display_name": doc.get("address_name", ""),
                    "latitude": float(doc.get("y", 0)),
                    "longitude": float(doc.get("x", 0)),
                    "category": doc.get("category_group_name", ""),
                    "phone": doc.get("phone", ""),
                    "place_url": doc.get("place_url", ""),
                    "source": "kakao",
                })
            return results

        except Exception as e:
            print(f"⚠️ 카카오 장소 검색 실패: {e}")
            return []

    async def _search_sync(self, query: str, limit: int) -> list[dict]:
        """aiohttp 없을 때 동기 방식 fallback"""
        try:
            import urllib.request
            import urllib.parse
            import json

            encoded_query = urllib.parse.quote(query)
            url = f"{KAKAO_API_URL}?query={encoded_query}&size={min(limit, 15)}&sort=accuracy"

            req = urllib.request.Request(url)
            req.add_header("Authorization", f"KakaoAK {self.api_key}")

            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))

            await self._increment_counter()

            results = []
            for doc in data.get("documents", []):
                results.append({
                    "name": doc.get("place_name", query),
                    "display_name": doc.get("address_name", ""),
                    "latitude": float(doc.get("y", 0)),
                    "longitude": float(doc.get("x", 0)),
                    "category": doc.get("category_group_name", ""),
                    "phone": doc.get("phone", ""),
                    "place_url": doc.get("place_url", ""),
                    "source": "kakao",
                })
            return results

        except Exception as e:
            print(f"⚠️ 카카오 동기 검색 실패: {e}")
            return []

    async def get_daily_usage(self) -> dict:
        """오늘의 API 사용량"""
        today = date.today().isoformat()
        row = await db.fetch_one(
            "SELECT call_count FROM api_counters WHERE date = ? AND api_name = 'kakao_local'",
            (today,)
        )
        count = row["call_count"] if row else 0
        return {
            "date": today,
            "used": count,
            "limit": self.daily_limit,
            "remaining": max(0, self.daily_limit - count),
        }


# 싱글톤 인스턴스
kakao_service = KakaoLocalService()
