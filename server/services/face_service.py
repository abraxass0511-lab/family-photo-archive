"""
얼굴 인식 서비스 (face_recognition, 100% 오픈소스)
- 가족 구성원 얼굴 등록 (기준 사진 3~5장)
- 업로드 사진에서 얼굴 자동 태깅
- 128차원 얼굴 벡터 비교
"""

import io
import pickle
from pathlib import Path
from PIL import Image

from config import settings
from db.database import db

# face_recognition + numpy는 설치가 필요한 선택적 의존성
try:
    import numpy as np
    import face_recognition
    FACE_RECOGNITION_AVAILABLE = True
except ImportError:
    np = None
    FACE_RECOGNITION_AVAILABLE = False
    print("⚠️ face_recognition 또는 numpy 미설치. 얼굴 인식 기능이 비활성화됩니다.")
    print("   설치: pip install face_recognition numpy (dlib 필요)")


class FaceService:
    """얼굴 인식 및 태깅 서비스"""

    def __init__(self):
        self.face_data_dir = Path(settings.FACE_DATA_DIR)
        self.known_encodings: list[np.ndarray] = []
        self.known_person_ids: list[int] = []
        self._loaded = False

    async def load_known_faces(self):
        """DB에서 등록된 얼굴 벡터 로드"""
        if not FACE_RECOGNITION_AVAILABLE:
            return

        persons = await db.fetch_all("SELECT id, face_encoding FROM persons WHERE face_encoding IS NOT NULL")

        self.known_encodings = []
        self.known_person_ids = []

        for person in persons:
            try:
                encoding = pickle.loads(person["face_encoding"])
                self.known_encodings.append(encoding)
                self.known_person_ids.append(person["id"])
            except Exception as e:
                print(f"⚠️ 얼굴 벡터 로드 실패 (person_id={person['id']}): {e}")

        self._loaded = True
        print(f"✅ {len(self.known_encodings)}명의 얼굴 데이터 로드 완료")

    def detect_faces(self, image_bytes: bytes) -> list[dict]:
        """
        이미지에서 얼굴 검출 및 인식

        Returns:
            [
                {"person_id": 1, "person_name": "아빠", "confidence": 0.92},
                {"person_id": None, "person_name": "unknown", "confidence": 0.0},
            ]
        """
        if not FACE_RECOGNITION_AVAILABLE:
            return []

        if not self._loaded:
            return []

        try:
            # 이미지 로드
            img = Image.open(io.BytesIO(image_bytes))
            if img.mode != "RGB":
                img = img.convert("RGB")

            # numpy 배열로 변환
            img_array = np.array(img)

            # 얼굴 위치 검출
            face_locations = face_recognition.face_locations(img_array, model="hog")
            if not face_locations:
                return []

            # 얼굴 인코딩 (128차원 벡터)
            face_encodings = face_recognition.face_encodings(img_array, face_locations)

            results = []
            for encoding in face_encodings:
                if len(self.known_encodings) > 0:
                    # 기존 얼굴과 비교
                    distances = face_recognition.face_distance(self.known_encodings, encoding)
                    best_idx = int(np.argmin(distances))
                    best_distance = distances[best_idx]

                    # 거리 0.6 이하 = 동일 인물 (confidence = 1 - distance)
                    if best_distance <= 0.6:
                        confidence = round(1.0 - best_distance, 2)
                        results.append({
                            "person_id": self.known_person_ids[best_idx],
                            "person_name": None,  # DB에서 조회 필요
                            "confidence": confidence,
                        })
                    else:
                        results.append({
                            "person_id": None,
                            "person_name": "unknown",
                            "confidence": 0.0,
                        })
                else:
                    results.append({
                        "person_id": None,
                        "person_name": "unknown",
                        "confidence": 0.0,
                    })

            return results

        except Exception as e:
            print(f"⚠️ 얼굴 인식 실패: {e}")
            return []

    async def register_face(self, person_id: int, image_bytes: bytes) -> bool:
        """
        인물의 기준 얼굴 등록

        Args:
            person_id: 인물 DB ID
            image_bytes: 얼굴이 포함된 이미지
        """
        if not FACE_RECOGNITION_AVAILABLE:
            return False

        try:
            img = Image.open(io.BytesIO(image_bytes))
            if img.mode != "RGB":
                img = img.convert("RGB")

            img_array = np.array(img)
            encodings = face_recognition.face_encodings(img_array)

            if not encodings:
                print(f"⚠️ 이미지에서 얼굴을 찾을 수 없습니다 (person_id={person_id})")
                return False

            # 첫 번째 얼굴 인코딩 사용
            encoding = encodings[0]
            encoding_blob = pickle.dumps(encoding)

            # DB 업데이트
            await db.execute(
                "UPDATE persons SET face_encoding = ? WHERE id = ?",
                (encoding_blob, person_id)
            )

            # 메모리 캐시 갱신
            self.known_encodings.append(encoding)
            self.known_person_ids.append(person_id)

            # 얼굴 썸네일 저장
            face_locations = face_recognition.face_locations(img_array)
            if face_locations:
                top, right, bottom, left = face_locations[0]
                face_img = img.crop((left, top, right, bottom))
                face_thumb_path = self.face_data_dir / f"person_{person_id}_face.jpg"
                self.face_data_dir.mkdir(parents=True, exist_ok=True)
                face_img.save(str(face_thumb_path), "JPEG", quality=85)

                await db.execute(
                    "UPDATE persons SET sample_thumbnail = ? WHERE id = ?",
                    (str(face_thumb_path), person_id)
                )

            print(f"✅ 얼굴 등록 완료: person_id={person_id}")
            return True

        except Exception as e:
            print(f"❌ 얼굴 등록 실패: {e}")
            return False

    async def tag_photo_faces(self, photo_id: str, image_bytes: bytes) -> list[str]:
        """
        사진에서 얼굴 감지 후 자동 태깅

        Returns:
            인식된 인물 이름 목록
        """
        faces = self.detect_faces(image_bytes)
        tagged_names = []

        for face in faces:
            if face["person_id"] is not None:
                # 이미 등록된 인물 → 자동 태깅
                await db.execute(
                    """INSERT OR IGNORE INTO photo_persons (photo_id, person_id, confidence)
                       VALUES (?, ?, ?)""",
                    (photo_id, face["person_id"], face["confidence"])
                )

                # 인물 이름 조회
                person = await db.fetch_one(
                    "SELECT name FROM persons WHERE id = ?",
                    (face["person_id"],)
                )
                if person:
                    tagged_names.append(person["name"])

                # 사진 카운트 증가
                await db.execute(
                    "UPDATE persons SET photo_count = photo_count + 1 WHERE id = ?",
                    (face["person_id"],)
                )

        return tagged_names


# 싱글톤 인스턴스
face_service = FaceService()
