/**
 * 클라이언트 사이드 암호 인증 모듈
 * - SHA-256 해시 기반 비밀번호 검증
 * - AES-256-GCM 데이터 암호화/복호화
 * - sessionStorage 기반 세션 관리 (브라우저 닫으면 로그아웃)
 */

const Auth = (() => {
    const DEFAULT_PASSWORD_HASH = '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8'; // "password" for demo

    const SESSION_KEY = 'family_archive_auth';

    /**
     * SHA-256 해시 생성
     */
    async function sha256(message) {
        const encoder = new TextEncoder();
        const data = encoder.encode(message);
        const hash = await crypto.subtle.digest('SHA-256', data);
        return Array.from(new Uint8Array(hash))
            .map(b => b.toString(16).padStart(2, '0'))
            .join('');
    }

    /**
     * 비밀번호 검증
     */
    async function verify(password) {
        const hash = await sha256(password);
        const storedHash = getStoredHash();
        return hash === storedHash;
    }

    /**
     * 저장된 비밀번호 해시 조회
     */
    function getStoredHash() {
        if (window.__PHOTO_DATA && window.__PHOTO_DATA.passwordHash) {
            return window.__PHOTO_DATA.passwordHash;
        }
        return DEFAULT_PASSWORD_HASH;
    }

    /**
     * AES-256-GCM 키 파생 (Python deploy_service와 동일 파라미터)
     */
    async function deriveKey(password, saltBase64) {
        const encoder = new TextEncoder();
        const salt = base64ToBuffer(saltBase64);

        const keyMaterial = await crypto.subtle.importKey(
            'raw',
            encoder.encode(password),
            'PBKDF2',
            false,
            ['deriveKey']
        );

        return crypto.subtle.deriveKey(
            {
                name: 'PBKDF2',
                salt: salt,
                iterations: 100000,
                hash: 'SHA-256'
            },
            keyMaterial,
            { name: 'AES-GCM', length: 256 },
            false,
            ['decrypt']
        );
    }

    /**
     * AES-256-GCM 복호화 (Python 암호화 데이터 해독)
     */
    async function decrypt(password, encryptedData) {
        try {
            const key = await deriveKey(password, encryptedData.salt);
            const iv = base64ToBuffer(encryptedData.iv);
            const ciphertext = base64ToBuffer(encryptedData.ciphertext);

            const decrypted = await crypto.subtle.decrypt(
                { name: 'AES-GCM', iv: iv },
                key,
                ciphertext
            );

            const decoder = new TextDecoder();
            return JSON.parse(decoder.decode(decrypted));
        } catch (e) {
            console.error('복호화 실패:', e);
            return null;
        }
    }

    /**
     * Base64 → ArrayBuffer 변환
     */
    function base64ToBuffer(base64) {
        const binaryString = atob(base64);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }
        return bytes.buffer;
    }

    /**
     * 세션 생성 (로그인 성공 시)
     */
    function createSession(password) {
        const session = {
            authenticated: true,
            timestamp: Date.now(),
            expires: Date.now() + (24 * 60 * 60 * 1000), // 24시간 만료
            // 비밀번호는 sessionStorage에만 보관 (브라우저 닫으면 삭제)
            _k: btoa(password),
        };
        sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
    }

    /**
     * 세션에서 비밀번호 복원 (복호화용)
     */
    function getSessionPassword() {
        try {
            const session = JSON.parse(sessionStorage.getItem(SESSION_KEY));
            return session?._k ? atob(session._k) : null;
        } catch {
            return null;
        }
    }

    /**
     * 세션 확인
     */
    function isAuthenticated() {
        try {
            const session = JSON.parse(sessionStorage.getItem(SESSION_KEY));
            if (!session) return false;
            if (Date.now() > session.expires) {
                sessionStorage.removeItem(SESSION_KEY);
                return false;
            }
            return session.authenticated === true;
        } catch {
            return false;
        }
    }

    /**
     * 로그아웃
     */
    function logout() {
        sessionStorage.removeItem(SESSION_KEY);
    }

    return { sha256, verify, deriveKey, decrypt, base64ToBuffer, createSession, getSessionPassword, isAuthenticated, logout };
})();


/**
 * 로그인 핸들러
 */
async function handleLogin(event) {
    event.preventDefault();

    const input = document.getElementById('password-input');
    const errorMsg = document.getElementById('auth-error');
    const loginBtn = document.getElementById('login-btn');

    const password = input.value.trim();
    if (!password) return false;

    // 로딩 상태
    loginBtn.disabled = true;
    loginBtn.innerHTML = '<div class="spinner"></div>';

    const isValid = await Auth.verify(password);

    if (isValid) {
        Auth.createSession(password);
        errorMsg.classList.add('hidden');

        // 성공 애니메이션
        const authScreen = document.getElementById('auth-screen');
        authScreen.style.transition = 'opacity 0.4s ease, transform 0.4s ease';
        authScreen.style.opacity = '0';
        authScreen.style.transform = 'scale(1.05)';

        setTimeout(() => {
            authScreen.classList.remove('active');
            document.getElementById('app-screen').classList.add('active');
            initApp();
        }, 400);
    } else {
        errorMsg.classList.remove('hidden');
        input.value = '';
        input.focus();

        // 실패 진동 애니메이션
        const card = document.querySelector('.auth-card');
        card.style.animation = 'none';
        void card.offsetHeight; // reflow
        card.style.animation = 'shake 0.4s ease-in-out';
    }

    loginBtn.disabled = false;
    loginBtn.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14M12 5l7 7-7 7"/></svg>`;

    return false;
}


/**
 * 로그아웃 핸들러
 */
function handleLogout() {
    Auth.logout();

    const appScreen = document.getElementById('app-screen');
    appScreen.classList.remove('active');

    const authScreen = document.getElementById('auth-screen');
    authScreen.style.opacity = '1';
    authScreen.style.transform = 'scale(1)';
    authScreen.classList.add('active');

    document.getElementById('password-input').value = '';
}


/**
 * 초기 인증 상태 확인
 */
document.addEventListener('DOMContentLoaded', () => {
    if (Auth.isAuthenticated()) {
        document.getElementById('auth-screen').classList.remove('active');
        document.getElementById('app-screen').classList.add('active');
        initApp();
    } else {
        document.getElementById('password-input').focus();
    }
});
