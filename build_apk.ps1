# ============================================
# 포토백업 APK 빌드 스크립트
# - pubspec.yaml 빌드번호 자동 +1
# - 한글 경로 우회 (c:\src\photo-backup 사용)
# - 바탕화면에 포토백업_vXX.apk 복사
# ============================================

$ErrorActionPreference = "Stop"

# 경로 설정
$SrcDir = "c:\Users\YS\Desktop\안티그래피티\사진관리하는에이전트(포토)\app"
$BuildDir = "c:\src\photo-backup"
$Desktop = "C:\Users\YS\Desktop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  포토백업 APK 빌드 시작" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ──────────────────────────────────────────────
# 1. pubspec.yaml에서 현재 빌드번호 읽기
#    (-Raw 대신 Out-String 사용 — PowerShell 호환)
# ──────────────────────────────────────────────
$pubspec = Get-Content "$SrcDir\pubspec.yaml" | Out-String
if ($pubspec -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
    $versionName = $Matches[1]
    $oldBuild = [int]$Matches[2]
    $newBuild = $oldBuild + 1
    Write-Host ""
    Write-Host "  버전: v$oldBuild -> v$newBuild" -ForegroundColor Yellow
} else {
    Write-Host "  ERROR: pubspec.yaml에서 버전을 찾을 수 없습니다" -ForegroundColor Red
    exit 1
}

# ──────────────────────────────────────────────
# 2. pubspec.yaml 빌드번호 자동 증가
# ──────────────────────────────────────────────
$newPubspec = $pubspec -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $versionName+$newBuild"
Set-Content "$SrcDir\pubspec.yaml" -Value $newPubspec -NoNewline

# ★ 검증: 실제로 버전이 바뀌었는지 확인
$verifyPubspec = Get-Content "$SrcDir\pubspec.yaml" | Out-String
if ($verifyPubspec -match "version:\s*$versionName\+$newBuild") {
    Write-Host "  pubspec.yaml 업데이트 완료 (v$newBuild 확인됨)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: pubspec.yaml 버전 업데이트 실패! 파일 내용 확인 필요" -ForegroundColor Red
    exit 1
}

# ──────────────────────────────────────────────
# 3. 빌드 디렉토리에 소스 동기화
# ──────────────────────────────────────────────
Write-Host ""
Write-Host "  소스 동기화 중..." -ForegroundColor Gray
Copy-Item -Path "$SrcDir\lib\*" -Destination "$BuildDir\lib\" -Recurse -Force
Copy-Item -Path "$SrcDir\pubspec.yaml" -Destination "$BuildDir\pubspec.yaml" -Force
Copy-Item -Path "$SrcDir\android\app\src\main\AndroidManifest.xml" -Destination "$BuildDir\android\app\src\main\AndroidManifest.xml" -Force

# ★ 검증: 빌드 디렉토리 pubspec에도 새 버전이 반영됐는지 확인
$buildPubspec = Get-Content "$BuildDir\pubspec.yaml" | Out-String
if ($buildPubspec -match "version:\s*$versionName\+$newBuild") {
    Write-Host "  소스 동기화 완료 (빌드 디렉토리 v$newBuild 확인됨)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: 빌드 디렉토리 pubspec.yaml 동기화 실패!" -ForegroundColor Red
    exit 1
}

# ──────────────────────────────────────────────
# 4. flutter pub get
# ──────────────────────────────────────────────
Write-Host ""
Write-Host "  패키지 설치 중..." -ForegroundColor Gray
Push-Location $BuildDir
flutter pub get 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "  ERROR: flutter pub get 실패!" -ForegroundColor Red
    exit 1
}
Write-Host "  패키지 설치 완료" -ForegroundColor Green

# ──────────────────────────────────────────────
# 5. APK 빌드
# ──────────────────────────────────────────────
Write-Host ""
Write-Host "  APK 빌드 중... (1~3분 소요)" -ForegroundColor Yellow
$buildResult = flutter build apk --release 2>&1
$exitCode = $LASTEXITCODE
Pop-Location

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "  BUILD FAILED!" -ForegroundColor Red
    Write-Host $buildResult
    exit 1
}

# ★ 검증: APK 파일이 실제로 생성됐는지 확인
$apkSrc = "$BuildDir\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSrc)) {
    Write-Host "  ERROR: APK 파일이 생성되지 않았습니다: $apkSrc" -ForegroundColor Red
    exit 1
}
$apkSize = [math]::Round((Get-Item $apkSrc).Length / 1MB, 1)
Write-Host "  APK 생성 완료 (${apkSize}MB)" -ForegroundColor Green

# ──────────────────────────────────────────────
# 6. 바탕화면에 복사 (cmd /c copy로 한글 경로 우회)
# ──────────────────────────────────────────────
$apkDst = "$Desktop\포토백업_v$newBuild.apk"
cmd /c copy /Y "$apkSrc" "$apkDst" > $null 2>&1

# ★ 검증: 바탕화면에 실제로 복사됐는지 확인
if (-not (Test-Path $apkDst)) {
    Write-Host "  WARNING: 바탕화면 복사 실패. 수동 복사 필요:" -ForegroundColor Yellow
    Write-Host "    $apkSrc" -ForegroundColor Gray
} else {
    $dstSize = [math]::Round((Get-Item $apkDst).Length / 1MB, 1)
    Write-Host "  바탕화면 복사 완료 (${dstSize}MB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  빌드 성공! v$newBuild" -ForegroundColor Green
Write-Host "  $apkDst" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
