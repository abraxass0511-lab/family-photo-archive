/**
 * 메인 앱 로직
 * - 데이터 로드 및 상태 관리
 * - 뷰 전환
 * - 즐겨찾기 관리
 */

// === 글로벌 상태 ===
let appState = {
    photos: [],
    places: [],
    persons: [],
    currentView: 'map',
    favoritesFilter: false,
    selectedPhotoId: null,
};

// === 데모 데이터 (서버 연동 전 테스트용) ===
const DEMO_DATA = {
    passwordHash: '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
    photos: [
        {
            id: 'demo1', filename: '가족여행_제주도.jpg',
            taken_at: '2024-08-15T14:30:00', latitude: 33.4507, longitude: 126.5706,
            place_name: '제주도 성산일출봉', is_backed_up: true, is_favorite: true,
            thumbnail_url: null, persons: ['아빠', '엄마', '아들'],
        },
        {
            id: 'demo2', filename: '크리스마스_저녁.jpg',
            taken_at: '2024-12-25T18:00:00', latitude: 37.5665, longitude: 126.9780,
            place_name: '서울 우리집', is_backed_up: true, is_favorite: false,
            thumbnail_url: null, persons: ['엄마', '딸'],
        },
        {
            id: 'demo3', filename: '봄소풍_한강.jpg',
            taken_at: '2025-04-12T11:20:00', latitude: 37.5283, longitude: 126.9340,
            place_name: '여의도 한강공원', is_backed_up: false, is_favorite: true,
            thumbnail_url: null, persons: ['아빠', '아들'],
        },
        {
            id: 'demo4', filename: '생일파티.jpg',
            taken_at: '2025-03-01T19:30:00', latitude: 37.5172, longitude: 127.0473,
            place_name: '강남 VIPS', is_backed_up: true, is_favorite: false,
            thumbnail_url: null, persons: ['아빠', '엄마', '아들', '딸'],
        },
        {
            id: 'demo5', filename: '등산_북한산.jpg',
            taken_at: '2025-05-03T09:15:00', latitude: 37.6584, longitude: 126.9784,
            place_name: '북한산 백운대', is_backed_up: true, is_favorite: true,
            thumbnail_url: null, persons: ['아빠'],
        },
        {
            id: 'demo6', filename: '부산여행_해운대.jpg',
            taken_at: '2024-07-20T16:40:00', latitude: 35.1587, longitude: 129.1604,
            place_name: '해운대 해수욕장', is_backed_up: true, is_favorite: false,
            thumbnail_url: null, persons: ['엄마', '딸'],
        },
    ],
    places: [
        { id: 1, name: '제주도 성산일출봉', latitude: 33.4507, longitude: 126.5706, photo_count: 1 },
        { id: 2, name: '서울 우리집', latitude: 37.5665, longitude: 126.9780, photo_count: 1 },
        { id: 3, name: '여의도 한강공원', latitude: 37.5283, longitude: 126.9340, photo_count: 1 },
        { id: 4, name: '강남 VIPS', latitude: 37.5172, longitude: 127.0473, photo_count: 1 },
        { id: 5, name: '북한산 백운대', latitude: 37.6584, longitude: 126.9784, photo_count: 1 },
        { id: 6, name: '해운대 해수욕장', latitude: 35.1587, longitude: 129.1604, photo_count: 1 },
    ],
    persons: [
        { id: 1, name: '아빠', photo_count: 4 },
        { id: 2, name: '엄마', photo_count: 3 },
        { id: 3, name: '아들', photo_count: 3 },
        { id: 4, name: '딸', photo_count: 2 },
    ],
};


/**
 * 앱 초기화
 */
function initApp() {
    console.log('📸 가족 추억 보관 상자 앱 초기화...');
    loadData();
}


/**
 * 데이터 로드
 */
async function loadData() {
    try {
        // data/photos.json 파일 로드 시도
        const response = await fetch('data/photos.json');
        if (response.ok) {
            const rawData = await response.json();
            window.__PHOTO_DATA = rawData;

            // 암호화 여부 확인
            if (rawData.encrypted === true) {
                // AES-256-GCM 암호화 데이터 → 복호화 필요
                console.log('🔐 암호화된 데이터 감지, 복호화 시도...');
                const password = Auth.getSessionPassword();

                if (!password) {
                    console.error('❌ 세션에 비밀번호 없음. 재로그인 필요');
                    throw new Error('No session password');
                }

                const decrypted = await Auth.decrypt(password, rawData);
                if (decrypted) {
                    console.log('✅ 복호화 성공!');
                    appState.photos = decrypted.photos || [];
                    appState.places = decrypted.places || [];
                    appState.persons = decrypted.persons || [];
                } else {
                    console.error('❌ 복호화 실패 — 비밀번호 불일치');
                    throw new Error('Decryption failed');
                }
            } else {
                // 비암호화 데이터 (개발/테스트용)
                appState.photos = rawData.photos || [];
                appState.places = rawData.places || [];
                appState.persons = rawData.persons || [];
            }
        } else {
            throw new Error('photos.json not found');
        }
    } catch (e) {
        // 데모 데이터 사용
        console.log('ℹ️ photos.json 미발견 또는 복호화 실패, 데모 데이터 사용');
        window.__PHOTO_DATA = DEMO_DATA;
        appState.photos = DEMO_DATA.photos;
        appState.places = DEMO_DATA.places;
        appState.persons = DEMO_DATA.persons;
    }

    // 뷰 렌더링
    initMap();
    renderGallery();
    renderPeople();
}


/**
 * 뷰 전환
 */
function switchView(viewName) {
    appState.currentView = viewName;

    // 네비게이션 버튼 활성화
    document.querySelectorAll('.nav-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.view === viewName);
    });

    // 뷰 전환
    document.querySelectorAll('.view').forEach(view => {
        view.classList.remove('active');
    });
    document.getElementById(`${viewName}-view`).classList.add('active');

    // 지도 뷰 전환 시 리사이즈
    if (viewName === 'map' && window.__map) {
        setTimeout(() => window.__map.invalidateSize(), 100);
    }
}


/**
 * 즐겨찾기 필터 토글
 */
function toggleFavoritesFilter() {
    appState.favoritesFilter = !appState.favoritesFilter;

    const btn = document.getElementById('fav-filter-btn');
    btn.classList.toggle('active', appState.favoritesFilter);

    renderGallery();
    updateMapMarkers();
}


/**
 * 즐겨찾기 토글 (사진 상세 모달에서)
 */
function toggleFavorite() {
    if (!appState.selectedPhotoId) return;

    const photo = appState.photos.find(p => p.id === appState.selectedPhotoId);
    if (photo) {
        photo.is_favorite = !photo.is_favorite;

        const favBtn = document.getElementById('modal-fav-btn');
        favBtn.classList.toggle('active', photo.is_favorite);

        // 갤러리 업데이트
        renderGallery();
    }
}


/**
 * 사진 모달 열기
 */
function openModal(photoId) {
    const photo = appState.photos.find(p => p.id === photoId);
    if (!photo) return;

    appState.selectedPhotoId = photoId;

    const modal = document.getElementById('photo-modal');
    const img = document.getElementById('modal-image');
    const dateEl = document.getElementById('modal-date').querySelector('span');
    const placeEl = document.getElementById('modal-place').querySelector('span');
    const personsEl = document.getElementById('modal-persons').querySelector('span');
    const favBtn = document.getElementById('modal-fav-btn');

    // 썸네일 또는 플레이스홀더
    img.src = photo.thumbnail_url || generatePlaceholder(photo);

    // 메타데이터
    dateEl.textContent = photo.taken_at
        ? new Date(photo.taken_at).toLocaleDateString('ko-KR', { year: 'numeric', month: 'long', day: 'numeric' })
        : '날짜 없음';
    placeEl.textContent = photo.place_name || '위치 미상';
    personsEl.textContent = photo.persons?.length ? photo.persons.join(', ') : '인물 없음';

    // 즐겨찾기 상태
    favBtn.classList.toggle('active', photo.is_favorite);

    modal.classList.remove('hidden');

    // ESC로 닫기
    document.addEventListener('keydown', handleModalKeydown);
}


/**
 * 모달 닫기
 */
function closeModal() {
    document.getElementById('photo-modal').classList.add('hidden');
    appState.selectedPhotoId = null;
    document.removeEventListener('keydown', handleModalKeydown);
}

function handleModalKeydown(e) {
    if (e.key === 'Escape') closeModal();
}


/**
 * 플레이스홀더 이미지 생성 (썸네일 없을 때)
 */
function generatePlaceholder(photo) {
    const colors = [
        '#7c6aef', '#4ecdc4', '#f7a072', '#ff6b9d',
        '#45b7d1', '#96ceb4', '#ffeaa7', '#dfe6e9'
    ];
    const color = colors[Math.abs(hashCode(photo.id)) % colors.length];
    const text = photo.place_name?.substring(0, 2) || '📸';

    // SVG 플레이스홀더
    const svg = `
        <svg xmlns="http://www.w3.org/2000/svg" width="320" height="320">
            <rect width="100%" height="100%" fill="${color}"/>
            <text x="50%" y="45%" text-anchor="middle" dy=".3em"
                  font-family="sans-serif" font-size="48" fill="white" opacity="0.9">${text}</text>
            <text x="50%" y="62%" text-anchor="middle" dy=".3em"
                  font-family="sans-serif" font-size="14" fill="white" opacity="0.6">
                ${photo.taken_at ? new Date(photo.taken_at).toLocaleDateString('ko-KR') : ''}
            </text>
        </svg>
    `;
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
}

function hashCode(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        hash = ((hash << 5) - hash) + str.charCodeAt(i);
        hash |= 0;
    }
    return hash;
}


/**
 * 하단 갤러리 토글 (지도 뷰)
 */
function toggleBottomGallery() {
    document.getElementById('bottom-gallery').classList.toggle('hidden');
}
