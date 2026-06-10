/**
 * 사진 업로드 모듈
 * - JWT 인증 + multipart 업로드
 * - 진행률 표시
 * - 중복 감지 + 폴더명 표시
 */

let authToken = null;

/** 서버 로그인 (JWT 토큰 발급) */
async function getAuthToken() {
    if (authToken) return authToken;

    try {
        const resp = await fetch('/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: 'admin', password: 'Admin1234!' }),
        });
        if (resp.ok) {
            const data = await resp.json();
            authToken = data.access_token;
            return authToken;
        }
    } catch (e) {
        console.error('로그인 실패:', e);
    }
    return null;
}

/** 업로드 모달 열기 */
function openUploadModal() {
    document.getElementById('upload-modal').classList.remove('hidden');
    document.getElementById('upload-progress').style.display = 'none';
    document.getElementById('upload-results').style.display = 'none';
    document.getElementById('upload-input').value = '';
}

/** 업로드 모달 닫기 */
function closeUploadModal() {
    document.getElementById('upload-modal').classList.add('hidden');
}

/** 파일 선택 핸들러 */
async function handleFileSelect(event) {
    const files = event.target.files;
    if (!files || files.length === 0) return;

    const token = await getAuthToken();
    if (!token) {
        alert('서버 인증 실패. 서버가 실행 중인지 확인하세요.');
        return;
    }

    const progressDiv = document.getElementById('upload-progress');
    const statusEl = document.getElementById('upload-status');
    const countEl = document.getElementById('upload-count');
    const barEl = document.getElementById('upload-bar');
    const resultsDiv = document.getElementById('upload-results');

    progressDiv.style.display = 'block';
    resultsDiv.style.display = 'block';
    resultsDiv.innerHTML = '';

    let completed = 0;
    let successCount = 0;
    let skipCount = 0;
    const total = files.length;

    for (const file of files) {
        statusEl.textContent = `업로드 중: ${file.name}`;
        countEl.textContent = `${completed}/${total}`;

        try {
            const formData = new FormData();
            formData.append('file', file);

            const resp = await fetch('/api/photos/upload', {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${token}` },
                body: formData,
            });

            completed++;
            const pct = Math.round((completed / total) * 100);
            barEl.style.width = `${pct}%`;
            countEl.textContent = `${completed}/${total}`;

            if (resp.ok) {
                const data = await resp.json();
                const location = data.extracted_metadata?.place_name || data.filename || file.name;
                successCount++;
                resultsDiv.innerHTML += `
                    <div style="display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 13px;">
                        <span style="color: #4ecdc4;">✅</span>
                        <span style="color: var(--text-secondary); flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(file.name)}</span>
                        <span style="color: var(--text-muted); font-size: 11px;">저장됨</span>
                    </div>`;
            } else if (resp.status === 409) {
                // 중복 — 건너뛰기
                skipCount++;
                resultsDiv.innerHTML += `
                    <div style="display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 13px;">
                        <span style="color: #ffd166;">⏭️</span>
                        <span style="color: var(--text-secondary); flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(file.name)}</span>
                        <span style="color: var(--text-muted); font-size: 11px;">이미 저장됨 (건너뜀)</span>
                    </div>`;
            } else {
                const errData = await resp.json().catch(() => ({}));
                resultsDiv.innerHTML += `
                    <div style="display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 13px;">
                        <span style="color: #ff4d6d;">❌</span>
                        <span style="color: var(--text-secondary);">${escapeHtml(file.name)} - ${errData.detail || '실패'}</span>
                    </div>`;
            }
        } catch (e) {
            completed++;
            resultsDiv.innerHTML += `
                <div style="display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 13px;">
                    <span style="color: #ff4d6d;">❌</span>
                    <span style="color: var(--text-secondary);">${escapeHtml(file.name)} - 네트워크 오류</span>
                </div>`;
        }
    }

    let summary = `✅ ${successCount}장 저장 완료`;
    if (skipCount > 0) summary += ` / ⏭️ ${skipCount}장 중복 건너뜀`;
    statusEl.textContent = summary;
    barEl.style.width = '100%';
}

/** HTML 이스케이프 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
