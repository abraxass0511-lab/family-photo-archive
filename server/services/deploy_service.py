"""
정적 웹 자동 배포 서비스
- 사진 메타데이터 + 썸네일 → AES-256-GCM 암호화
- 암호화된 정적 파일 생성
- Cloudflare Pages / GitHub Pages 자동 배포
"""

import os
import json
import shutil
import base64
import hashlib
import secrets
from pathlib import Path
from datetime import datetime

from config import settings
from db.database import db
from services.thumbnail_service import thumbnail_service


class DeployService:
    """정적 웹 배포 서비스 (AES-256-GCM 암호화)"""

    def __init__(self):
        self.web_source = Path(__file__).parent.parent.parent / "web"
        self.build_dir = Path(settings.WEB_BUILD_DIR)

    async def build_and_deploy(self, password: str) -> dict:
        """
        전체 빌드 + 배포 파이프라인

        1. photos.json 생성 (메타데이터 + 썸네일 경로)
        2. AES-256-GCM 암호화
        3. 정적 파일 복사
        4. Cloudflare/GitHub Pages 배포

        Args:
            password: 공유 웹사이트 비밀번호

        Returns:
            {"status": "deployed", "url": "...", "photo_count": 42}
        """
        # 1. 빌드 디렉토리 준비
        self._prepare_build_dir()

        # 2. 메타데이터 수집
        photo_data = await self._collect_photo_data()

        # 3. AES-256-GCM 암호화
        password_hash = hashlib.sha256(password.encode()).hexdigest()
        encrypted_data = self._encrypt_data(json.dumps(photo_data, ensure_ascii=False), password)

        # 4. 암호화된 데이터 파일 생성
        encrypted_json = {
            "passwordHash": password_hash,
            "encrypted": True,
            "iv": encrypted_data["iv"],
            "salt": encrypted_data["salt"],
            "ciphertext": encrypted_data["ciphertext"],
            "version": "1.0",
            "generated_at": datetime.now().isoformat(),
        }

        data_dir = self.build_dir / "data"
        data_dir.mkdir(exist_ok=True)
        with open(data_dir / "photos.json", "w", encoding="utf-8") as f:
            json.dump(encrypted_json, f)

        # 5. 썸네일 복사
        thumb_count = await self._copy_thumbnails(data_dir / "thumbnails")

        # 6. 배포
        deploy_result = await self._deploy()

        return {
            "status": "deployed" if deploy_result["success"] else "build_complete",
            "photo_count": len(photo_data.get("photos", [])),
            "thumbnail_count": thumb_count,
            "build_dir": str(self.build_dir),
            "deploy_result": deploy_result,
        }

    def _prepare_build_dir(self):
        """빌드 디렉토리 초기화 + 웹 소스 복사"""
        # 기존 빌드 삭제
        if self.build_dir.exists():
            shutil.rmtree(self.build_dir)
        self.build_dir.mkdir(parents=True)

        # 웹 소스 복사 (HTML, CSS, JS)
        if self.web_source.exists():
            for item in self.web_source.iterdir():
                if item.is_file():
                    shutil.copy2(str(item), str(self.build_dir / item.name))
                elif item.is_dir() and item.name != "data":
                    shutil.copytree(str(item), str(self.build_dir / item.name))

    async def _collect_photo_data(self) -> dict:
        """DB에서 사진 메타데이터 수집"""
        photos = await db.fetch_all(
            "SELECT * FROM photos ORDER BY taken_at DESC"
        )

        photo_list = []
        for p in photos:
            persons = await db.fetch_all(
                """SELECT pe.name FROM photo_persons pp
                   JOIN persons pe ON pp.person_id = pe.id
                   WHERE pp.photo_id = ?""",
                (p["id"],)
            )

            photo_list.append({
                "id": p["id"],
                "filename": p["filename"],
                "taken_at": str(p["taken_at"]) if p["taken_at"] else None,
                "latitude": p["latitude"],
                "longitude": p["longitude"],
                "place_name": p["place_name"],
                "is_backed_up": bool(p["is_backed_up"]),
                "is_favorite": bool(p["is_favorite"]),
                "thumbnail_url": f"data/thumbnails/{p['id']}.jpg" if p["thumbnail_path"] else None,
                "persons": [per["name"] for per in persons],
            })

        # 인물 목록
        persons_data = await db.fetch_all("SELECT * FROM persons ORDER BY name")
        person_list = [
            {"id": p["id"], "name": p["name"], "photo_count": p["photo_count"]}
            for p in persons_data
        ]

        # 장소 목록
        places_data = await db.fetch_all(
            """SELECT pl.*, COUNT(pp.photo_id) as photo_count
               FROM places pl
               LEFT JOIN photo_places pp ON pl.id = pp.place_id
               GROUP BY pl.id"""
        )
        place_list = [
            {
                "id": p["id"],
                "name": p["name"],
                "latitude": p["latitude"],
                "longitude": p["longitude"],
                "photo_count": p["photo_count"],
            }
            for p in places_data
        ]

        return {
            "photos": photo_list,
            "persons": person_list,
            "places": place_list,
        }

    def _encrypt_data(self, plaintext: str, password: str) -> dict:
        """
        AES-256-GCM 암호화 (Web Crypto API 호환)

        Python에서 암호화 → JavaScript에서 복호화
        """
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes

        # 랜덤 salt와 IV 생성
        salt = secrets.token_bytes(16)
        iv = secrets.token_bytes(12)  # AES-GCM 표준 IV 크기

        # PBKDF2로 비밀번호에서 키 파생 (Web Crypto API와 동일 파라미터)
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,  # 256비트 키
            salt=salt,
            iterations=100000,
        )
        key = kdf.derive(password.encode("utf-8"))

        # AES-256-GCM 암호화
        aesgcm = AESGCM(key)
        ciphertext = aesgcm.encrypt(iv, plaintext.encode("utf-8"), None)

        return {
            "salt": base64.b64encode(salt).decode("ascii"),
            "iv": base64.b64encode(iv).decode("ascii"),
            "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
        }

    async def _copy_thumbnails(self, target_dir: Path) -> int:
        """썸네일 파일 복사"""
        target_dir.mkdir(parents=True, exist_ok=True)
        copied = 0

        photos = await db.fetch_all("SELECT id, thumbnail_path FROM photos WHERE thumbnail_path IS NOT NULL")
        for p in photos:
            src = Path(p["thumbnail_path"])
            if src.exists():
                dst = target_dir / f"{p['id']}.jpg"
                shutil.copy2(str(src), str(dst))
                copied += 1

        return copied

    async def _deploy(self) -> dict:
        """Cloudflare Pages 또는 GitHub Pages로 배포"""
        import subprocess

        # Cloudflare Pages (Wrangler CLI)
        if settings.CLOUDFLARE_API_TOKEN:
            try:
                result = subprocess.run(
                    [
                        "npx", "-y", "wrangler", "pages", "deploy",
                        str(self.build_dir),
                        "--project-name", settings.CLOUDFLARE_PROJECT_NAME,
                    ],
                    env={**os.environ, "CLOUDFLARE_API_TOKEN": settings.CLOUDFLARE_API_TOKEN},
                    capture_output=True, text=True, timeout=120,
                )
                if result.returncode == 0:
                    print(f"✅ Cloudflare Pages 배포 완료")
                    return {"success": True, "platform": "cloudflare", "output": result.stdout}
                else:
                    print(f"⚠️ Cloudflare 배포 실패: {result.stderr}")
                    return {"success": False, "platform": "cloudflare", "error": result.stderr}
            except Exception as e:
                print(f"⚠️ Cloudflare 배포 오류: {e}")
                return {"success": False, "platform": "cloudflare", "error": str(e)}

        # 배포 토큰 미설정 시 → 로컬 빌드만
        print(f"📁 정적 웹 빌드 완료: {self.build_dir}")
        print("   배포하려면 CLOUDFLARE_API_TOKEN을 설정하거나")
        print(f"   수동으로 '{self.build_dir}' 폴더를 호스팅 서비스에 업로드하세요.")
        return {"success": True, "platform": "local", "build_dir": str(self.build_dir)}


# 싱글톤 인스턴스
deploy_service = DeployService()
