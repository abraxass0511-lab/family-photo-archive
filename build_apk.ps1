# ============================================
# 포토백업 APK 빌드 스크립트
# - 한글 경로 완전 우회: cmd /c 사용
# - 매 단계 검증 + 실패 시 즉시 중단
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
# 1. 소스 동기화 (cmd /c xcopy로 한글 경로 우회)
# ──────────────────────────────────────────────
Write-Host ""
Write-Host "  소스 동기화 중..." -ForegroundColor Gray
cmd /c xcopy "$SrcDir\lib" "$BuildDir\lib" /E /Y /Q > $null 2>&1
cmd /c copy /Y "$SrcDir\pubspec.yaml" "$BuildDir\pubspec.yaml" > $null 2>&1
cmd /c copy /Y "$SrcDir\android\app\src\main\AndroidManifest.xml" "$BuildDir\android\app\src\main\AndroidManifest.xml" > $null 2>&1

# ★ 검증: 핵심 파일이 빌드 디렉토리에 존재하는지 확인
$checkFiles = @(
    "$BuildDir\lib\providers\transfer_provider.dart",
    "$BuildDir\pubspec.yaml",
    "$BuildDir\android\app\src\main\AndroidManifest.xml"
)
foreach ($f in $checkFiles) {
    if (-not (Test-Path $f)) {
        Write-Host "  ERROR: 소스 동기화 실패! 파일 없음: $f" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  소스 동기화 완료 (파일 존재 확인됨)" -ForegroundColor Green

# ──────────────────────────────────────────────
# 2. pubspec.yaml 버전 읽기 + 증가 (빌드 디렉토리에서)
# ──────────────────────────────────────────────
$pubspec = Get-Content "$BuildDir\pubspec.yaml" | Out-String
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

# 빌드 디렉토리의 pubspec 버전 업데이트
$newPubspec = $pubspec -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $versionName+$newBuild"
Set-Content "$BuildDir\pubspec.yaml" -Value $newPubspec -NoNewline

# ★ 검증: 빌드 디렉토리 pubspec 버전 확인
$verifyPubspec = Get-Content "$BuildDir\pubspec.yaml" | Out-String
if ($verifyPubspec -match "version:\s*$versionName\+$newBuild") {
    Write-Host "  빌드 디렉토리 pubspec v$newBuild 확인됨" -ForegroundColor Green
} else {
    Write-Host "  ERROR: 빌드 디렉토리 pubspec 버전 업데이트 실패!" -ForegroundColor Red
    exit 1
}

# 원본 pubspec도 업데이트 (cmd /c copy로 역복사)
cmd /c copy /Y "$BuildDir\pubspec.yaml" "$SrcDir\pubspec.yaml" > $null 2>&1

# ──────────────────────────────────────────────
# 3. flutter pub get
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
# 4. APK 빌드
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

# ★ 검증: APK 파일 존재 확인
$apkSrc = "$BuildDir\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSrc)) {
    Write-Host "  ERROR: APK 파일이 생성되지 않았습니다!" -ForegroundColor Red
    exit 1
}
$apkSize = [math]::Round((Get-Item $apkSrc).Length / 1MB, 1)
Write-Host "  APK 생성 완료 (${apkSize}MB)" -ForegroundColor Green

# ──────────────────────────────────────────────
# 5. 바탕화면에 복사 (cmd /c copy로 한글 경로 우회)
# ──────────────────────────────────────────────
$apkDst = "$Desktop\포토백업_v$newBuild.apk"
cmd /c copy /Y "$apkSrc" "$apkDst" > $null 2>&1

# ★ 검증: 바탕화면 복사 확인
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
