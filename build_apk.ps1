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

# 1. pubspec.yaml에서 현재 빌드번호 읽기
$pubspec = Get-Content "$SrcDir\pubspec.yaml" -Raw
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

# 2. pubspec.yaml 빌드번호 자동 증가
$newPubspec = $pubspec -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $versionName+$newBuild"
Set-Content "$SrcDir\pubspec.yaml" -Value $newPubspec -NoNewline
Write-Host "  pubspec.yaml 업데이트 완료" -ForegroundColor Green

# 3. 빌드 디렉토리에 소스 동기화
Write-Host ""
Write-Host "  소스 동기화 중..." -ForegroundColor Gray
Copy-Item -Path "$SrcDir\lib\*" -Destination "$BuildDir\lib\" -Recurse -Force
Copy-Item -Path "$SrcDir\pubspec.yaml" -Destination "$BuildDir\pubspec.yaml" -Force
Write-Host "  소스 동기화 완료" -ForegroundColor Green

# 4. flutter pub get
Write-Host ""
Write-Host "  패키지 설치 중..." -ForegroundColor Gray
Push-Location $BuildDir
flutter pub get 2>&1 | Out-Null
Write-Host "  패키지 설치 완료" -ForegroundColor Green

# 5. APK 빌드
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

# 6. 바탕화면에 복사
$apkSrc = "$BuildDir\build\app\outputs\flutter-apk\app-release.apk"
$apkDst = "$Desktop\포토백업_v$newBuild.apk"
Copy-Item $apkSrc -Destination $apkDst -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  빌드 성공! v$newBuild" -ForegroundColor Green
Write-Host "  $apkDst" -ForegroundColor Green  
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
