/**
 * 지도 모듈 (Leaflet.js + OpenStreetMap, 100% 무료)
 * - 마커 클러스터링
 * - 핀 클릭 → 하단 갤러리 연동
 * - 다크 모드 타일
 */

// 지도 인스턴스
window.__map = null;
let markerCluster = null;


/**
 * 지도 초기화
 */
function initMap() {
    if (window.__map) {
        window.__map.remove();
    }

    // 대한민국 중심 좌표
    const defaultCenter = [36.5, 127.5];
    const defaultZoom = 7;

    // Leaflet 지도 생성
    window.__map = L.map('map-container', {
        center: defaultCenter,
        zoom: defaultZoom,
        zoomControl: true,
        attributionControl: true,
    });

    // 다크 모드 타일 (CartoDB Dark Matter, 100% 무료)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>',
        subdomains: 'abcd',
        maxZoom: 19,
    }).addTo(window.__map);

    // 마커 클러스터 레이어
    markerCluster = L.markerClusterGroup({
        maxClusterRadius: 50,
        spiderfyOnMaxZoom: true,
        showCoverageOnHover: false,
        iconCreateFunction: function(cluster) {
            const count = cluster.getChildCount();
            let size = 'small';
            if (count >= 10) size = 'medium';
            if (count >= 50) size = 'large';

            return L.divIcon({
                html: `<div class="custom-marker">${count}</div>`,
                className: `marker-cluster marker-cluster-${size}`,
                iconSize: L.point(40, 40),
            });
        }
    });

    window.__map.addLayer(markerCluster);

    // 마커 추가
    updateMapMarkers();
}


/**
 * 지도 마커 업데이트
 */
function updateMapMarkers() {
    if (!markerCluster) return;

    markerCluster.clearLayers();

    // 장소별 사진 그룹핑
    const placeGroups = {};

    const filteredPhotos = appState.favoritesFilter
        ? appState.photos.filter(p => p.is_favorite)
        : appState.photos;

    filteredPhotos.forEach(photo => {
        if (photo.latitude && photo.longitude) {
            const key = `${photo.latitude.toFixed(4)}_${photo.longitude.toFixed(4)}`;
            if (!placeGroups[key]) {
                placeGroups[key] = {
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    place_name: photo.place_name || '위치 미상',
                    photos: [],
                };
            }
            placeGroups[key].photos.push(photo);
        }
    });

    // 각 장소에 마커 추가
    Object.values(placeGroups).forEach(group => {
        const marker = L.marker([group.latitude, group.longitude], {
            icon: L.divIcon({
                html: `<div class="custom-marker">${group.photos.length}</div>`,
                className: '',
                iconSize: L.point(36, 36),
                iconAnchor: L.point(18, 18),
            }),
        });

        // 팝업 콘텐츠 (XSS 방어: HTML 이스케이프)
        const safeName = escapeHtml(group.place_name);
        marker.bindPopup(`
            <div style="min-width:150px">
                <strong style="font-size:14px">${safeName}</strong>
                <p style="margin:4px 0 0;font-size:12px;color:#9896a8">${group.photos.length}장의 사진</p>
            </div>
        `, { closeButton: false });

        // 클릭 → 하단 갤러리
        marker.on('click', () => {
            showBottomGallery(group.place_name, group.photos);
        });

        markerCluster.addLayer(marker);
    });

    // 마커가 있으면 영역에 맞게 줌
    if (markerCluster.getLayers().length > 0) {
        try {
            window.__map.fitBounds(markerCluster.getBounds(), { padding: [40, 40] });
        } catch (e) {
            // 마커가 1개인 경우 에러 방지
        }
    }
}


/**
 * 하단 갤러리 표시 (지도 핀 클릭 시)
 */
function showBottomGallery(placeName, photos) {
    const gallery = document.getElementById('bottom-gallery');
    const nameEl = document.getElementById('gallery-place-name');
    const countEl = document.getElementById('gallery-photo-count');
    const scrollEl = document.getElementById('gallery-scroll');

    nameEl.textContent = placeName;
    countEl.textContent = `${photos.length}장`;

    // 갤러리 아이템 렌더링
    scrollEl.innerHTML = photos.map(photo => `
        <div class="gallery-scroll-item" onclick="openModal('${escapeHtml(photo.id)}')">
            <img src="${photo.thumbnail_url || generatePlaceholder(photo)}"
                 alt="${escapeHtml(photo.place_name || '')}"
                 loading="lazy">
            ${photo.is_favorite ? '<span class="fav-indicator">❤️</span>' : ''}
        </div>
    `).join('');

    gallery.classList.remove('hidden');
}


/**
 * HTML 이스케이프 (XSS 방어 — CVE-2025-69993 대응)
 */
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
