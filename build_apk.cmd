@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

REM ============================================
REM Photo Backup APK Build Script
REM - Korean path safe (uses cmd.exe natively)
REM - Validates every step
REM ============================================

set "SRC=c:\Users\YS\Desktop\안티그래피티\사진관리하는에이전트(포토)\app"
set "BUILD=c:\src\photo-backup"
set "DESKTOP=C:\Users\YS\Desktop"

echo.
echo ========================================
echo   APK Build Start
echo ========================================

REM 1. Sync source to build dir
echo.
echo   [1/5] Syncing source...
xcopy "%SRC%\lib" "%BUILD%\lib" /E /Y /Q >nul 2>&1
if errorlevel 1 (
    echo   ERROR: lib sync failed!
    exit /b 1
)
copy /Y "%SRC%\pubspec.yaml" "%BUILD%\pubspec.yaml" >nul 2>&1
if errorlevel 1 (
    echo   ERROR: pubspec.yaml sync failed!
    exit /b 1
)
copy /Y "%SRC%\android\app\src\main\AndroidManifest.xml" "%BUILD%\android\app\src\main\AndroidManifest.xml" >nul 2>&1

REM Verify key file exists
if not exist "%BUILD%\lib\providers\transfer_provider.dart" (
    echo   ERROR: transfer_provider.dart not found in build dir!
    exit /b 1
)
if not exist "%BUILD%\pubspec.yaml" (
    echo   ERROR: pubspec.yaml not found in build dir!
    exit /b 1
)

REM Verify the code change is present
findstr /C:"transferredAssetIds.add(item.asset.id)" "%BUILD%\lib\providers\transfer_provider.dart" | find /C /V "" > "%BUILD%\_count.tmp"
set /p MATCH_COUNT=<"%BUILD%\_count.tmp"
del "%BUILD%\_count.tmp"
if "%MATCH_COUNT%" LSS "2" (
    echo   ERROR: Code change not found! transferredAssetIds.add should appear 2 times, found %MATCH_COUNT%
    exit /b 1
)
echo   Source sync OK (code change verified: %MATCH_COUNT% matches)

REM 2. Read current version and bump
echo.
echo   [2/5] Bumping version...
for /f "tokens=2 delims=+" %%a in ('findstr "version:" "%BUILD%\pubspec.yaml"') do set "OLD_BUILD=%%a"
set /a NEW_BUILD=%OLD_BUILD%+1
echo   Version: v%OLD_BUILD% -^> v%NEW_BUILD%

REM Update version in build dir pubspec
powershell -Command "(Get-Content '%BUILD%\pubspec.yaml' | Out-String) -replace 'version: 1\.0\.0\+%OLD_BUILD%', 'version: 1.0.0+%NEW_BUILD%' | Set-Content '%BUILD%\pubspec.yaml' -NoNewline"

REM Verify version updated
findstr "version: 1.0.0+%NEW_BUILD%" "%BUILD%\pubspec.yaml" >nul 2>&1
if errorlevel 1 (
    echo   ERROR: Version bump failed! pubspec still shows old version.
    exit /b 1
)
echo   Version bump OK (v%NEW_BUILD% confirmed)

REM Copy updated pubspec back to source
copy /Y "%BUILD%\pubspec.yaml" "%SRC%\pubspec.yaml" >nul 2>&1

REM 3. Flutter pub get
echo.
echo   [3/5] Installing packages...
cd /d "%BUILD%"
call flutter pub get >nul 2>&1
if errorlevel 1 (
    echo   ERROR: flutter pub get failed!
    exit /b 1
)
echo   Packages OK

REM 4. Build APK
echo.
echo   [4/5] Building APK... (1-3 min)
call flutter build apk --release 2>&1
if errorlevel 1 (
    echo   ERROR: APK build failed!
    exit /b 1
)

REM Verify APK exists
if not exist "%BUILD%\build\app\outputs\flutter-apk\app-release.apk" (
    echo   ERROR: APK file not created!
    exit /b 1
)
echo   APK build OK

REM 5. Copy to desktop
echo.
echo   [5/5] Copying to desktop...
set "APK_DST=%DESKTOP%\포토백업_v%NEW_BUILD%.apk"
copy /Y "%BUILD%\build\app\outputs\flutter-apk\app-release.apk" "%APK_DST%" >nul 2>&1

if not exist "%APK_DST%" (
    echo   WARNING: Desktop copy failed. Manual copy needed:
    echo     %BUILD%\build\app\outputs\flutter-apk\app-release.apk
) else (
    echo   Desktop copy OK
)

echo.
echo ========================================
echo   BUILD SUCCESS! v%NEW_BUILD%
echo   %APK_DST%
echo ========================================
echo.
