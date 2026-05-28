# 📸 가족 추억 보관 상자

> **클라우드 제로(Self-Hosted) 기반의 위치·인물 매칭 가족 사진 아카이브 시스템**

대기업 클라우드 없이 개인 외장하드를 메인 저장소로 활용하여, 스마트폰 용량을 무한대로 확보하는 **폐쇄형 사진 관리 솔루션**.

## ✨ 핵심 기능

| 기능 | 설명 |
|------|------|
| 🔒 **클라우드 제로** | 구글 포토/네이버 없이 개인 외장하드에 원본 격리 |
| 📱 **폰 메모리 해방** | 원본은 외장하드로, 폰에는 썸네일+DB만 유지 |
| 🗺️ **지도 기반 검색** | OpenStreetMap + 카카오 로컬 API (100% 무료) |
| 👨‍👩‍👧‍👦 **AI 인물 인식** | face_recognition으로 자동 태그 |
| 🌐 **24시간 웹 공유** | AES-256 암호화 정적 웹 (Cloudflare Pages) |
| 🔐 **데이터 무결성** | SHA-256 체크섬 크로스 체크 |

## 🏗️ 아키텍처

```
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│   Flutter App    │      │  Python Backend  │      │   Static Web     │
│   (iOS/Android)  │◄────►│  (FastAPI)       │─────►│  (AES-256 암호화)│
│   로컬 SQLite    │      │  외장하드 관리    │      │  Cloudflare Pages│
└──────────────────┘      └──────────────────┘      └──────────────────┘
         │                        │
         └── 썸네일 + DB ──────── 원본 → 외장하드
```

## 🛠️ 기술 스택 (100% 무료)

| 영역 | 기술 | 비용 |
|------|------|------|
| 백엔드 | Python, FastAPI, SQLite | ✅ 무료 |
| 모바일 | Flutter, sqflite, flutter_map | ✅ 무료 |
| 지도 | OpenStreetMap + CartoDB 다크 타일 | ✅ 무료 |
| 장소 검색 | 카카오 로컬 API (10만건/일) + Nominatim | ✅ 무료 |
| 얼굴 인식 | face_recognition (dlib) | ✅ 무료 |
| 웹 호스팅 | Cloudflare Pages / GitHub Pages | ✅ 무료 |
| 암호화 | AES-256-GCM (Web Crypto API) | ✅ 무료 |

## 📁 프로젝트 구조

```
├── server/          # Python 백엔드 (FastAPI)
│   ├── main.py
│   ├── config.py
│   ├── services/    # 카카오API, EXIF, 얼굴인식, 배포 등
│   ├── routers/     # REST API 엔드포인트
│   ├── db/          # SQLite 데이터베이스
│   └── utils/       # 외장하드 감시 등
│
├── app/             # Flutter 모바일 앱
│   ├── pubspec.yaml
│   └── lib/
│       ├── screens/ # 지도, 갤러리, 인물, 설정
│       ├── providers/
│       ├── services/
│       └── db/
│
├── web/             # 정적 공유 웹사이트
│   ├── index.html
│   ├── css/
│   └── js/          # AES-256 복호화, 지도, 갤러리
│
└── build_exe.py     # PyInstaller .exe 빌드
```

## 🚀 설치 및 실행

### 백엔드 서버

```bash
cd server
python -m venv venv
venv\Scripts\activate       # Windows
pip install -r requirements.txt
cp .env.example .env        # 환경변수 설정
python main.py
```

### GitHub Secrets 설정

| Secret 이름 | 용도 |
|-------------|------|
| `KAKAO_REST_API_KEY` | 카카오 로컬 API 키 |
| `CLOUDFLARE_API_TOKEN` | Cloudflare Pages 배포 토큰 |
| `WEB_PASSWORD` | 공유 웹사이트 비밀번호 |

## 📝 라이선스

Private — 가족 전용
