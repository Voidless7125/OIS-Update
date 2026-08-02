@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Objects in Space - Community Patch

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PATCH_VERSION="
set "REQUIRED_DLLS=OpenAL32.dll fmod.dll glew32.dll iconv.dll libbrotlicommon.dll libbrotlidec.dll libcocos2d.dll libcrypto-1_1.dll libcrypto-3.dll libcurl.dll libgcc_s_dw2-1.dll libiconv-2.dll libidn2-0.dll libintl-8.dll libmpg123.dll libnghttp2-14.dll libpsl-5.dll libssl-1_1.dll libssl-3.dll libtiff.dll libunistring-5.dll libvorbis.dll libvorbisfile.dll libwinpthread-1.dll libzstd.dll ogg.dll sqlite3.dll steam_api.dll websockets.dll zlib1.dll"
set "DEBUG_MODE=0"
set "TARGET_OVERRIDE="

call :PrintHeader
call :ParseArgs %* || goto :Fail
call :LoadPatchVersion
call :ValidatePayload || goto :Fail
call :OfferUpdateCheck
if errorlevel 2 goto :UpdateDownloadedExit
call :DetectTarget "%TARGET_OVERRIDE%" || goto :Fail
call :ShowInstalledVersion
call :ConfirmTarget || goto :Fail
call :EnsureGameClosed || goto :Fail
call :CopyLibraries || goto :Fail
call :VerifyRuntimeFiles || goto :Fail
call :CompareAgainstOriginal
call :WriteInstallMarker || goto :Fail
call :OfferFirewall
call :Finish
exit /b 0

:PrintHeader
echo ===================================================
echo   Objects in Space: Community Patch Setup
echo ===================================================
echo.
echo This tool validates all patch files, updates game files,
echo and records the installed patch version.
echo.
echo Optional argument: -debug  ^(shows per-file compare details^)
echo.
exit /b 0

:ParseArgs
if "%~1"=="" exit /b 0

if /I "%~1"=="-debug" (
    set "DEBUG_MODE=1"
    shift
    goto :ParseArgs
)
if /I "%~1"=="--debug" (
    set "DEBUG_MODE=1"
    shift
    goto :ParseArgs
)
if /I "%~1"=="/debug" (
    set "DEBUG_MODE=1"
    shift
    goto :ParseArgs
)

if defined TARGET_OVERRIDE (
    echo [ERROR] Only one target game folder path can be provided.
    echo.
    pause
    exit /b 1
)
set "TARGET_OVERRIDE=%~1"
shift
goto :ParseArgs

:LoadPatchVersion
if exist "%SCRIPT_DIR%\VERSION.txt" (
    for /f "usebackq delims=" %%V in ("%SCRIPT_DIR%\VERSION.txt") do (
        if not defined PATCH_VERSION set "PATCH_VERSION=%%V"
    )
)
if not defined PATCH_VERSION set "PATCH_VERSION=unknown"
echo Patch package version: %PATCH_VERSION%
echo.
exit /b 0

:ValidatePayload
echo Validating patch package files...
setlocal EnableDelayedExpansion
set /a MISSING_COUNT=0
for %%F in (%REQUIRED_DLLS%) do (
    if not exist "%SCRIPT_DIR%\%%~F" (
        echo [ERROR] Missing required patch file: %%~F
        set /a MISSING_COUNT+=1
    )
)
if !MISSING_COUNT! gtr 0 (
    endlocal
    echo.
    echo [ERROR] The patch package is incomplete.
    echo Please download/extract the patch again and rerun this script.
    echo.
    pause
    exit /b 1
)
endlocal
echo Package validation complete.
echo.
exit /b 0

:DetectTarget
set "TARGET_DIR="

if not "%~1"=="" set "TARGET_DIR=%~1"
if defined TARGET_DIR (
    call :IsValidGameDir "%TARGET_DIR%" && exit /b 0
    echo [ERROR] The folder passed to Patch_OIS.bat is not a valid game folder:
    echo "%TARGET_DIR%"
    echo.
    pause
    exit /b 1
)

if defined OIS_TARGET_DIR (
    set "TARGET_DIR=%OIS_TARGET_DIR%"
    call :IsValidGameDir "%TARGET_DIR%" && exit /b 0
    set "TARGET_DIR="
)

for %%I in ("%ProgramFiles(x86)%\Steam" "%ProgramFiles%\Steam" "%USERPROFILE%\Steam") do (
    call :IsValidGameDir "%%~I\steamapps\common\Objects in Space" >nul 2>&1
    if not errorlevel 1 (
        set "TARGET_DIR=%%~I\steamapps\common\Objects in Space"
        exit /b 0
    )
)

for %%K in ("HKCU\Software\Valve\Steam" "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" "HKLM\SOFTWARE\Valve\Steam") do (
    for /f "tokens=2,*" %%A in ('reg query "%%~K" /v InstallPath 2^>nul ^| findstr /R /C:"InstallPath"') do (
        call :IsValidGameDir "%%~B\steamapps\common\Objects in Space" >nul 2>&1
        if not errorlevel 1 (
            set "TARGET_DIR=%%~B\steamapps\common\Objects in Space"
            exit /b 0
        )
    )
)

setlocal EnableDelayedExpansion
echo [NOTICE] Could not automatically find the game folder.
echo.
echo Please copy and paste your Objects in Space install folder path.
echo Example: D:\SteamLibrary\steamapps\common\Objects in Space
set /p "USER_TARGET=Game folder path: "
if not defined USER_TARGET (
    endlocal
    echo.
    echo [ERROR] No folder path was entered.
    pause
    exit /b 1
)
endlocal & set "TARGET_DIR=%USER_TARGET%"
call :IsValidGameDir "%TARGET_DIR%" && exit /b 0

echo.
echo [ERROR] The folder does not look like an Objects in Space install:
echo "%TARGET_DIR%"
echo.
pause
exit /b 1

:IsValidGameDir
if exist "%~1\ois.exe" exit /b 0
if exist "%~1\ois_server.exe" exit /b 0
exit /b 1

:ShowInstalledVersion
if exist "%TARGET_DIR%\OIS_Update.version.txt" (
    echo Existing patch marker found in game folder:
    for /f "usebackq delims=" %%L in ("%TARGET_DIR%\OIS_Update.version.txt") do echo   %%L
    echo.
) else (
    echo No existing patch marker found in game folder.
    echo.
)
exit /b 0

:ConfirmTarget
echo Game folder found:
echo "%TARGET_DIR%"
echo.
choice /C YN /M "Continue with this folder?"
if errorlevel 2 (
    echo.
    echo Setup canceled by user.
    pause
    exit /b 1
)
exit /b 0

:EnsureGameClosed
tasklist /FI "IMAGENAME eq ois.exe" 2>nul | find /I "ois.exe" >nul
if not errorlevel 1 (
    echo.
    echo [ERROR] ois.exe is currently running.
    echo Please close the game and run this script again.
    echo.
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq ois_server.exe" 2>nul | find /I "ois_server.exe" >nul
if not errorlevel 1 (
    echo.
    echo [ERROR] ois_server.exe is currently running.
    echo Please close the server and run this script again.
    echo.
    pause
    exit /b 1
)
exit /b 0

:CopyLibraries
echo [1/5] Copying updated game files...

if exist "%TARGET_DIR%\libogg.dll" (
    echo       Removing obsolete libogg.dll...
    del /F /Q "%TARGET_DIR%\libogg.dll" >nul 2>&1
)

setlocal EnableDelayedExpansion
set /a COPIED_COUNT=0
for %%F in (%REQUIRED_DLLS%) do (
    if exist "%SCRIPT_DIR%\%%~F:Zone.Identifier" del /F /Q "%SCRIPT_DIR%\%%~F:Zone.Identifier" >nul 2>&1
    copy /Y "%SCRIPT_DIR%\%%~F" "%TARGET_DIR%\%%~F" >nul
    if errorlevel 1 (
        endlocal
        echo [ERROR] Failed to copy "%%~F".
        echo.
        pause
        exit /b 1
    )
    if exist "%TARGET_DIR%\%%~F:Zone.Identifier" del /F /Q "%TARGET_DIR%\%%~F:Zone.Identifier" >nul 2>&1
    set /a COPIED_COUNT+=1
)
endlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%SCRIPT_DIR%' -Filter '*.dll' -File | Unblock-File -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath '%TARGET_DIR%' -Filter '*.dll' -File | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
echo       Copy complete.
echo.
exit /b 0

:VerifyRuntimeFiles
echo [2/5] Verifying installed files match this patch...
setlocal EnableDelayedExpansion
set /a VERIFY_COUNT=0
for %%F in (%REQUIRED_DLLS%) do (
    if not exist "%TARGET_DIR%\%%~F" (
        endlocal
        echo [ERROR] Missing required file in game folder: %%~F
        echo.
        pause
        exit /b 1
    )
    fc /b "%SCRIPT_DIR%\%%~F" "%TARGET_DIR%\%%~F" >nul
    if errorlevel 2 (
        endlocal
        echo [ERROR] Could not verify file: %%~F
        echo.
        pause
        exit /b 1
    )
    if errorlevel 1 (
        endlocal
        echo [ERROR] Installed file does not match this patch: %%~F
        echo.
        pause
        exit /b 1
    )
    set /a VERIFY_COUNT+=1
)
echo       Verified !VERIFY_COUNT! file^(s^) successfully.
endlocal
echo.
exit /b 0

:CompareAgainstOriginal
echo [3/5] Comparing installed files to Original baseline...
if not exist "%SCRIPT_DIR%\Original\*.dll" (
    echo       Original baseline folder not found. Skipping comparison.
    echo.
    exit /b 0
)

setlocal EnableDelayedExpansion
set /a SAME_COUNT=0
set /a DIFFERENT_COUNT=0
set /a MISSING_COUNT=0
for %%F in ("%SCRIPT_DIR%\Original\*.dll") do (
    set "NAME=%%~nxF"
    if not exist "%TARGET_DIR%\!NAME!" (
        set /a MISSING_COUNT+=1
        if "%DEBUG_MODE%"=="1" echo       MISSING: !NAME!
    ) else (
        fc /b "%%~fF" "%TARGET_DIR%\!NAME!" >nul
        if errorlevel 2 (
            set /a MISSING_COUNT+=1
            if "%DEBUG_MODE%"=="1" echo       MISSING: !NAME! ^(compare error^)
        ) else if errorlevel 1 (
            set /a DIFFERENT_COUNT+=1
            if "%DEBUG_MODE%"=="1" echo       DIFFERENT: !NAME!
        ) else (
            set /a SAME_COUNT+=1
            if "%DEBUG_MODE%"=="1" echo       SAME: !NAME!
        )
    )
)
echo       Different from Original: !DIFFERENT_COUNT!
echo       Same as Original:        !SAME_COUNT!
echo       Missing vs Original:     !MISSING_COUNT!
endlocal
echo.
exit /b 0

:WriteInstallMarker
echo [4/5] Writing patch version marker...
(
    echo OIS Community Patch
    echo Version=%PATCH_VERSION%
    echo Installed=%DATE% %TIME%
    echo Source=%SCRIPT_DIR%
    echo Script=Patch_OIS.bat
) > "%TARGET_DIR%\OIS_Update.version.txt"
if errorlevel 1 (
    echo [ERROR] Could not write version marker to game folder.
    echo.
    pause
    exit /b 1
)
echo       Wrote: "%TARGET_DIR%\OIS_Update.version.txt"
echo.
exit /b 0

:OfferFirewall
echo [5/5] Optional security hardening
echo Recommended: block inbound connections for this legacy game.
echo.
choice /C YN /M "Apply recommended Windows Firewall protection for this game now?"
if errorlevel 2 (
    echo.
    echo Firewall changes were skipped.
    echo.
    exit /b 0
)

call :ApplyFirewall
if errorlevel 1 (
    echo [WARNING] Firewall rules were not confirmed.
    echo This usually means the admin prompt was canceled or blocked.
    echo.
    exit /b 0
)

echo Firewall rules applied successfully.
echo.
exit /b 0

:ApplyFirewall
echo.
echo Windows may show an Administrator permission prompt.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/d /c netsh advfirewall firewall delete rule name=\"OIS_Client_Block_Inbound\" >nul 2^>^&1 & netsh advfirewall firewall delete rule name=\"OIS_Server_Block_Inbound\" >nul 2^>^&1 & netsh advfirewall firewall add rule name=\"OIS_Client_Block_Inbound\" description=\"Community Patch: Blocks inbound connections to secure legacy libwebsockets.\" dir=in action=block program=\"%TARGET_DIR%\ois.exe\" enable=yes profile=any edge=no >nul & netsh advfirewall firewall add rule name=\"OIS_Server_Block_Inbound\" description=\"Community Patch: Blocks inbound connections to secure legacy libwebsockets.\" dir=in action=block program=\"%TARGET_DIR%\ois_server.exe\" enable=yes profile=any edge=no >nul' -Verb RunAs -Wait"

netsh advfirewall firewall show rule name="OIS_Client_Block_Inbound" | findstr /I /C:"Rule Name:" >nul
if errorlevel 1 exit /b 1
netsh advfirewall firewall show rule name="OIS_Server_Block_Inbound" | findstr /I /C:"Rule Name:" >nul
if errorlevel 1 exit /b 1
exit /b 0

:OfferUpdateCheck
echo.
choice /C YN /M "Check online for a newer patch and download it now?"
if errorlevel 2 exit /b 0

set "PATCH_LOCAL_VERSION=%PATCH_VERSION%"
set "PATCH_SCRIPT_DIR=%SCRIPT_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $localVersion=$env:PATCH_LOCAL_VERSION; if ([string]::IsNullOrWhiteSpace($localVersion)) { $localVersion='unknown' }; $scriptDir=$env:PATCH_SCRIPT_DIR; $versionUrl='https://raw.githubusercontent.com/Voidless7125/OIS-Update/dev/VERSION.txt'; $zipUrl='https://github.com/Voidless7125/OIS-Update/archive/refs/heads/dev.zip'; $remote=((Invoke-WebRequest -UseBasicParsing -Uri $versionUrl -TimeoutSec 20).Content -split '\r?\n')[0].Trim(); if ([string]::IsNullOrWhiteSpace($remote)) { throw 'Remote version is empty.' }; if ($remote -eq $localVersion) { Write-Host 'No update found. You already have the latest version.'; exit 0 }; $downloadDir=Join-Path $scriptDir 'Downloads'; New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null; $zipPath=Join-Path $downloadDir ('OIS-Update-' + $remote + '.zip'); Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zipPath -TimeoutSec 120; Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue; Write-Host ('Downloaded new version: ' + $remote); Write-Host ('Saved to: ' + $zipPath); exit 10" >nul
if errorlevel 10 (
    echo New patch package downloaded to:
    echo "%SCRIPT_DIR%\Downloads"
    echo.
    choice /C YN /M "Continue installing this current package anyway?"
    if errorlevel 2 exit /b 2
    exit /b 0
)
if errorlevel 1 (
    echo [WARNING] Could not check/download updates right now.
    echo.
    exit /b 0
)
echo You already have the latest patch package.
echo.
exit /b 0

:UpdateDownloadedExit
echo.
echo Setup canceled so you can use the newly downloaded package.
echo.
pause
exit /b 0

:Finish
echo ===================================================
echo   SUCCESS! Objects in Space is ready to play.
echo.
echo Installed patch version: %PATCH_VERSION%
echo Version marker file:
echo "%TARGET_DIR%\OIS_Update.version.txt"
echo.
echo If you have crashes or issues, report them here:
echo https://steamcommunity.com/app/824070/discussions/0/573795849686060451/
echo ===================================================
echo.
pause
exit /b 0

:Fail
echo.
echo Setup did not complete.
exit /b 1