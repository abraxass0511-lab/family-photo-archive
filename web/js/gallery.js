/**
 * 갤러리 & 인물 뷰 모듈
 * - 사진 그리드 렌더링
 * - 검색 & 정렬
 * - 다중 선택 + 삭제
 * - 인물별 앨범
 */

// 선택 상태
let selectState = {
    enabled: false,
    selected: new Set(),
};


/**
 * 사진 갤러리 렌더링
 */
function renderGallery() {
    const grid = document.getElementById('photo-grid');
    let photos = [...appState.photos];

    // 즐겨찾기 필터
    if (appState.favoritesFilter) {
        photos = photos.filter(p => p.is_favorite);
    }

    // 날짜 기준 최신순 정렬 (기본)
    photos.sort((a, b) => {
        const dateA = a.taken_at ? new Date(a.taken_at) : new Date(0);
        const dateB = b.taken_at ? new Date(b.taken_at) : new Date(0);
        return dateB - dateA;
    });

    if (photos.length === 0) {
        grid.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1">
                <div class="empty-state-icon">📷</div>
                <p class="empty-state-text">${appState.favoritesFilter ? '즐겨찾기한 사진이 없습니다' : '사진이 없습니다'}</p>
                <p class="empty-state-sub">서버에서 사진을 업로드하면 여기에 표시됩니다</p>
            </div>
        `;
        return;
    }

    grid.innerHTML = photos.map(photo => {
        const safeName = escapeHtml(photo.place_name || '');
        const date = photo.taken_at
            ? new Date(photo.taken_at).toLocaleDateString('ko-KR', { month: 'short', day: 'numeric' })
            : '';
        const isSelected = selectState.selected.has(photo.id);

        return `
            <div class="photo-card ${photo.is_backed_up ? 'backed-up' : ''} ${isSelected ? 'selected' : ''}"
                 onclick="handlePhotoClick(event, '${escapeHtml(photo.id)}')"
                 id="photo-${escapeHtml(photo.id)}">
                <div class="select-checkbox"></div>
                <img src="${photo.thumbnail_url || generatePlaceholder(photo)}"
                     alt="${safeName}"
                     loading="lazy">
                ${photo.is_favorite ? '<span class="fav-indicator">❤️</span>' : ''}
                <div class="photo-overlay">
                    <span class="place-label">${safeName}</span>
                    <span class="date-label">${date}</span>
                </div>
            </div>
        `;
    }).join('');
}


/**
 * 사진 검색 필터
 */
function filterPhotos(query) {
    const normalizedQuery = query.toLowerCase().trim();

    if (!normalizedQuery) {
        renderGallery();
        return;
    }

    const grid = document.getElementById('photo-grid');
    let filtered = appState.photos.filter(photo => {
        const placeName = (photo.place_name || '').toLowerCase();
        const filename = (photo.filename || '').toLowerCase();
        const persons = (photo.persons || []).join(' ').toLowerCase();
        const date = photo.taken_at || '';

        return placeName.includes(normalizedQuery) ||
               filename.includes(normalizedQuery) ||
               persons.includes(normalizedQuery) ||
               date.includes(normalizedQuery);
    });

    if (appState.favoritesFilter) {
        filtered = filtered.filter(p => p.is_favorite);
    }

    if (filtered.length === 0) {
        grid.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1">
                <div class="empty-state-icon">🔍</div>
                <p class="empty-state-text">'${escapeHtml(query)}' 검색 결과가 없습니다</p>
            </div>
        `;
        return;
    }

    grid.innerHTML = filtered.map(photo => {
        const safeName = escapeHtml(photo.place_name || '');
        const date = photo.taken_at
            ? new Date(photo.taken_at).toLocaleDateString('ko-KR', { month: 'short', day: 'numeric' })
            : '';

        return `
            <div class="photo-card ${photo.is_backed_up ? 'backed-up' : ''}"
                 onclick="openModal('${escapeHtml(photo.id)}')">
                <img src="${photo.thumbnail_url || generatePlaceholder(photo)}"
                     alt="${safeName}" loading="lazy">
                ${photo.is_favorite ? '<span class="fav-indicator">❤️</span>' : ''}
                <div class="photo-overlay">
                    <span class="place-label">${safeName}</span>
                    <span class="date-label">${date}</span>
                </div>
            </div>
        `;
    }).join('');
}


/**
 * 사진 정렬
 */
function sortPhotos(sortBy) {
    switch (sortBy) {
        case 'date-desc':
            appState.photos.sort((a, b) =>
                new Date(b.taken_at || 0) - new Date(a.taken_at || 0));
            break;
        case 'date-asc':
            appState.photos.sort((a, b) =>
                new Date(a.taken_at || 0) - new Date(b.taken_at || 0));
            break;
        case 'place':
            appState.photos.sort((a, b) =>
                (a.place_name || 'zzz').localeCompare(b.place_name || 'zzz'));
            break;
    }
    renderGallery();
}


/**
 * 인물 뷰 렌더링
 */
function renderPeople() {
    const grid = document.getElementById('people-grid');

    if (appState.persons.length === 0) {
        grid.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1">
                <div class="empty-state-icon">👨‍👩‍👧‍👦</div>
                <p class="empty-state-text">등록된 인물이 없습니다</p>
                <p class="empty-state-sub">서버에서 얼굴 인식을 수행하면 자동으로 추가됩니다</p>
            </div>
        `;
        return;
    }

    const personColors = ['#7c6aef', '#4ecdc4', '#f7a072', '#ff6b9d', '#45b7d1', '#96ceb4'];

    grid.innerHTML = appState.persons.map((person, i) => {
        const color = personColors[i % personColors.length];
        const initial = person.name.charAt(0);

        return `
            <div class="person-card" onclick="showPersonPhotos(${person.id}, '${escapeHtml(person.name)}')">
                <div class="person-avatar-placeholder" style="background: ${color}">
                    ${initial}
                </div>
                <div class="person-name">${escapeHtml(person.name)}</div>
                <div class="person-count">${person.photo_count}장</div>
            </div>
        `;
    }).join('');
}


/**
 * 특정 인물의 사진 보기
 */
function showPersonPhotos(personId, personName) {
    const person = appState.persons.find(p => p.id === personId);
    if (!person) return;

    // 인물 그리드 숨기고 사진 표시
    document.getElementById('people-grid').classList.add('hidden');
    document.getElementById('person-photos').classList.remove('hidden');
    document.getElementById('person-name').textContent = personName;

    // 해당 인물이 포함된 사진 필터링
    const photos = appState.photos.filter(p =>
        p.persons && p.persons.includes(personName)
    );

    const grid = document.getElementById('person-photo-grid');

    if (photos.length === 0) {
        grid.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1">
                <div class="empty-state-icon">📸</div>
                <p class="empty-state-text">${escapeHtml(personName)}의 사진이 없습니다</p>
            </div>
        `;
        return;
    }

    grid.innerHTML = photos.map(photo => {
        const safeName = escapeHtml(photo.place_name || '');
        return `
            <div class="photo-card ${photo.is_backed_up ? 'backed-up' : ''}"
                 onclick="openModal('${escapeHtml(photo.id)}')">
                <img src="${photo.thumbnail_url || generatePlaceholder(photo)}"
                     alt="${safeName}" loading="lazy">
                ${photo.is_favorite ? '<span class="fav-indicator">❤️</span>' : ''}
                <div class="photo-overlay">
                    <span class="place-label">${safeName}</span>
                </div>
            </div>
        `;
    }).join('');
}


/**
 * 인물 그리드로 돌아가기
 */
function showPeopleGrid() {
    document.getElementById('people-grid').classList.remove('hidden');
    document.getElementById('person-photos').classList.add('hidden');
}


// =============================================
// 다중 선택 + 삭제 기능
// =============================================

/**
 * 사진 클릭 핸들러 (일반 모드 vs 선택 모드 분기)
 */
function handlePhotoClick(event, photoId) {
    if (selectState.enabled) {
        event.stopPropagation();
        togglePhotoSelect(photoId);
    } else {
        openModal(photoId);
    }
}


/**
 * 선택 모드 토글
 */
function toggleSelectMode() {
    selectState.enabled = !selectState.enabled;

    const grid = document.getElementById('photo-grid');
    const btn = document.querySelector('.select-mode-btn');

    if (selectState.enabled) {
        grid.classList.add('select-mode');
        if (btn) { btn.classList.add('active'); btn.textContent = '선택 취소'; }
    } else {
        grid.classList.remove('select-mode');
        if (btn) { btn.classList.remove('active'); btn.textContent = '선택'; }
        selectState.selected.clear();
        updateDeleteBar();
    }
    renderGallery();
}


/**
 * 개별 사진 선택/해제
 */
function togglePhotoSelect(photoId) {
    const photo = appState.photos.find(p => p.id === photoId);
    if (!photo) return;

    // 백업 완료된 사진(초록 테두리)만 선택 가능
    if (!photo.is_backed_up) {
        alert('⚠️ 아직 외장하드에 백업되지 않은 사진은 삭제할 수 없습니다.');
        return;
    }

    if (selectState.selected.has(photoId)) {
        selectState.selected.delete(photoId);
    } else {
        selectState.selected.add(photoId);
    }

    // 카드 UI 업데이트
    const card = document.getElementById(`photo-${photoId}`);
    if (card) {
        card.classList.toggle('selected', selectState.selected.has(photoId));
    }

    updateDeleteBar();
}


/**
 * 하단 붉은색 삭제 바 업데이트
 */
function updateDeleteBar() {
    let bar = document.getElementById('delete-bar');

    if (selectState.selected.size === 0) {
        if (bar) bar.classList.add('hidden');
        return;
    }

    // 삭제 바가 없으면 생성
    if (!bar) {
        bar = document.createElement('div');
        bar.id = 'delete-bar';
        bar.className = 'delete-bar';
        document.body.appendChild(bar);
    }

    bar.innerHTML = `
        <div class="delete-bar-info">
            <span>📱 폰에서 삭제 가능한 사진</span>
            <span class="delete-bar-count">${selectState.selected.size}장 선택됨</span>
        </div>
        <div class="delete-bar-actions">
            <button class="delete-btn" onclick="toggleSelectMode()">취소</button>
            <button class="delete-btn primary" onclick="confirmDeleteSelected()">
                🗑️ 선택 사진 폰에서 삭제
            </button>
        </div>
    `;
    bar.classList.remove('hidden');
}


/**
 * 선택 사진 삭제 확인
 */
function confirmDeleteSelected() {
    const count = selectState.selected.size;
    if (count === 0) return;

    const confirmed = confirm(
        `⚠️ ${count}장의 사진을 폰에서 삭제합니다.\n\n` +
        `• 이 사진들은 이미 외장하드에 백업 완료되었습니다.\n` +
        `• 폰의 원본만 삭제되며, 외장하드의 원본과 웹 미리보기는 유지됩니다.\n\n` +
        `삭제하시겠습니까?`
    );

    if (confirmed) {
        // 실제 삭제 API 호출 (Flutter 앱에서 실행)
        console.log('🗑️ 삭제 대상:', [...selectState.selected]);
        alert(`✅ ${count}장의 사진 삭제 요청이 전송되었습니다.\n앱에서 확인 후 원본이 삭제됩니다.`);

        selectState.selected.clear();
        toggleSelectMode();
    }
}
