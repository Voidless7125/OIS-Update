@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Objects in Space - Community Patch

rem =====================================================================
rem  Objects in Space: Community Patch Setup
rem  - Payload is DISCOVERED, not hardcoded (no more iconv.dll-style breaks)
rem  - Update check runs BEFORE payload validation (broken package can heal)
rem  - Downloads use curl.exe + tar.exe when available (much faster)
rem =====================================================================

set "REPO_OWNER=Voidless7125"
set "REPO_NAME=OIS-Update"
set "REPO_BRANCH=dev"
set "VERSION_URL=https://raw.githubusercontent.com/%REPO_OWNER%/%REPO_NAME%/%REPO_BRANCH%/VERSION.txt"
set "ZIP_URL=https://codeload.github.com/%REPO_OWNER%/%REPO_NAME%/zip/refs/heads/%REPO_BRANCH%"

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "BACKUP_DIR=%SCRIPT_DIR%\Backup"
set "PATCH_VERSION="
set "DEBUG_MODE=0"
set "TARGET_OVERRIDE="
set "PAYLOAD_LIST="
set "PAYLOAD_COUNT=0"
set "HAVE_CURL=0"
set "HAVE_TAR=0"

where curl.exe >nul 2>&1 && set "HAVE_CURL=1"
where tar.exe  >nul 2>&1 && set "HAVE_TAR=1"

call :PrintHeader
call :ParseArgs %* || goto :Fail
call :LoadPatchVersion
call :OfferUpdateCheck
if errorlevel 2 goto :UpdateDownloadedExit
call :BuildPayload || goto :Fail
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


rem ---------------------------------------------------------------- UI
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
if /I "%~1"=="-debug"  ( set "DEBUG_MODE=1" & shift & goto :ParseArgs )
if /I "%~1"=="--debug" ( set "DEBUG_MODE=1" & shift & goto :ParseArgs )
if /I "%~1"=="/debug"  ( set "DEBUG_MODE=1" & shift & goto :ParseArgs )
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
call :NormalizeVersion PATCH_VERSION
echo Patch package version: %PATCH_VERSION%
echo.
exit /b 0


rem ------------------------------------------------------- payload build
rem Payload = manifest.txt if present, otherwise every *.dll sitting next
rem to this script. This is the actual fix for the iconv.dll breakage:
rem the file list can no longer drift out of sync with the package.
:BuildPayload
echo Building patch file list...
set "PAYLOAD_LIST="
set /a PAYLOAD_COUNT=0
set /a MISSING_COUNT=0
if exist "%SCRIPT_DIR%\manifest.txt" (
    for /f "usebackq eol=# tokens=* delims=" %%F in ("%SCRIPT_DIR%\manifest.txt") do call :AddPayload "%%~F"
) else (
    for %%F in ("%SCRIPT_DIR%\*.dll") do call :AddPayload "%%~nxF"
)
if %PAYLOAD_COUNT% EQU 0 (
    echo [ERROR] No patch files found next to this script.
    echo Expected .dll files in: "%SCRIPT_DIR%"
    echo Please re-extract the patch package and run this script from inside it.
    echo.
    pause
    exit /b 1
)
if %MISSING_COUNT% GTR 0 (
    echo.
    echo [ERROR] The patch package is incomplete ^(%MISSING_COUNT% file^(s^) listed but not present^).
    echo Please download/extract the patch again and rerun this script.
    echo.
    pause
    exit /b 1
)
echo Found %PAYLOAD_COUNT% patch file^(s^).
echo.
exit /b 0


:AddPayload
set "PF=%~1"
if not defined PF exit /b 0
if not exist "%SCRIPT_DIR%\%PF%" (
    echo [ERROR] Listed in manifest but missing from package: %PF%
    set /a MISSING_COUNT+=1
    exit /b 0
)
set PAYLOAD_LIST=%PAYLOAD_LIST% "%PF%"
set /a PAYLOAD_COUNT+=1
exit /b 0


rem ------------------------------------------------------ target folder
:DetectTarget
set "TARGET_DIR="

if not "%~1"=="" (
    set "TARGET_DIR=%~1"
    call :NormalizePath TARGET_DIR
    call :IsValidGameDir "%~1" >nul 2>&1
)
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
    call :NormalizePath TARGET_DIR
    call :IsValidGameDir "%OIS_TARGET_DIR%" >nul 2>&1
    if not errorlevel 1 exit /b 0
    set "TARGET_DIR="
)

for %%I in ("%ProgramFiles(x86)%\Steam" "%ProgramFiles%\Steam" "%USERPROFILE%\Steam" "%SystemDrive%\Steam") do (
    call :IsValidGameDir "%%~I\steamapps\common\Objects in Space" >nul 2>&1
    if not errorlevel 1 (
        set "TARGET_DIR=%%~I\steamapps\common\Objects in Space"
        exit /b 0
    )
)

for %%K in ("HKCU\Software\Valve\Steam" "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" "HKLM\SOFTWARE\Valve\Steam") do (
    for /f "tokens=2,*" %%A in ('reg query "%%~K" /v InstallPath 2^>nul ^| findstr /R /C:"InstallPath"') do (
        call :ScanSteamRoot "%%~B"
        if not errorlevel 1 exit /b 0
    )
)

echo [NOTICE] Could not automatically find the game folder.
echo.
echo Please copy and paste your Objects in Space install folder path.
echo Example: D:\SteamLibrary\steamapps\common\Objects in Space
set "USER_TARGET="
set /p "USER_TARGET=Game folder path: "
if not defined USER_TARGET (
    echo.
    echo [ERROR] No folder path was entered.
    echo.
    pause
    exit /b 1
)
set "TARGET_DIR=%USER_TARGET%"
call :NormalizePath TARGET_DIR
call :IsValidGameDir "%TARGET_DIR%" && exit /b 0

echo.
echo [ERROR] The folder does not look like an Objects in Space install:
echo "%TARGET_DIR%"
echo.
pause
exit /b 1


rem Checks the default library AND any extra libraries listed in libraryfolders.vdf
:ScanSteamRoot
set "STEAM_ROOT=%~1"
call :IsValidGameDir "%STEAM_ROOT%\steamapps\common\Objects in Space" >nul 2>&1
if not errorlevel 1 (
    set "TARGET_DIR=%STEAM_ROOT%\steamapps\common\Objects in Space"
    exit /b 0
)
if not exist "%STEAM_ROOT%\steamapps\libraryfolders.vdf" exit /b 1
for /f "usebackq tokens=2 delims=	 " %%P in (`findstr /I /C:"\"path\"" "%STEAM_ROOT%\steamapps\libraryfolders.vdf"`) do (
    call :TrySteamLibrary %%P
    if not errorlevel 1 exit /b 0
)
exit /b 1


:TrySteamLibrary
set "LIB=%~1"
if not defined LIB exit /b 1
call :IsValidGameDir "%LIB%\steamapps\common\Objects in Space" >nul 2>&1
if errorlevel 1 exit /b 1
set "TARGET_DIR=%LIB%\steamapps\common\Objects in Space"
exit /b 0


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
    echo.
    pause
    exit /b 1
)
exit /b 0


:EnsureGameClosed
call :CheckProcess ois.exe        || exit /b 1
call :CheckProcess ois_server.exe || exit /b 1
exit /b 0

:CheckProcess
tasklist /FI "IMAGENAME eq %~1" 2>nul | find /I "%~1" >nul
if errorlevel 1 exit /b 0
echo.
echo [ERROR] %~1 is currently running.
echo Please close it and run this script again.
echo.
pause
exit /b 1


rem ------------------------------------------------------------- install
:CopyLibraries
echo [1/5] Copying updated game files...
call :RemoveObsolete
if not exist "%BACKUP_DIR%" md "%BACKUP_DIR%" >nul 2>&1
set /a COPIED_COUNT=0
for %%F in (%PAYLOAD_LIST%) do call :CopyOne "%%~F" || goto :CopyFailed
call :UnblockFiles
echo       Copied %COPIED_COUNT% file^(s^).
echo       Pre-patch originals kept in: "%BACKUP_DIR%"
echo.
exit /b 0

:CopyFailed
echo.
pause
exit /b 1

:CopyOne
if exist "%TARGET_DIR%\%~1" (
    if not exist "%BACKUP_DIR%\%~1" copy /Y "%TARGET_DIR%\%~1" "%BACKUP_DIR%\%~1" >nul 2>&1
)
copy /Y "%SCRIPT_DIR%\%~1" "%TARGET_DIR%\%~1" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy "%~1".
    echo Make sure the game is closed and you have write access to the game folder.
    exit /b 1
)
set /a COPIED_COUNT+=1
exit /b 0


rem Files the patch used to install but no longer ships, AND that the base
rem game does not need. Do NOT add iconv.dll here: it was only dropped from
rem the patch payload, the original game copy should stay in place.
:RemoveObsolete
if exist "%SCRIPT_DIR%\obsolete.txt" (
    for /f "usebackq eol=# tokens=* delims=" %%F in ("%SCRIPT_DIR%\obsolete.txt") do call :DeleteObsolete "%%~F"
    exit /b 0
)
call :DeleteObsolete "libogg.dll"
exit /b 0

:DeleteObsolete
if not defined TARGET_DIR exit /b 0
if not exist "%TARGET_DIR%\%~1" exit /b 0
echo       Removing obsolete %~1...
if not exist "%BACKUP_DIR%" md "%BACKUP_DIR%" >nul 2>&1
if not exist "%BACKUP_DIR%\%~1" copy /Y "%TARGET_DIR%\%~1" "%BACKUP_DIR%\%~1" >nul 2>&1
del /F /Q "%TARGET_DIR%\%~1" >nul 2>&1
exit /b 0


rem copy.exe does not carry alternate data streams, so this is belt-and-braces
rem for files that already had Mark-of-the-Web in the game folder.
:UnblockFiles
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Get-ChildItem -LiteralPath '%TARGET_DIR%' -Filter '*.dll' -File | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
exit /b 0


:VerifyRuntimeFiles
echo [2/5] Verifying installed files match this patch...
set /a VERIFY_COUNT=0
for %%F in (%PAYLOAD_LIST%) do call :VerifyOne "%%~F" || goto :VerifyFailed
echo       Verified %VERIFY_COUNT% file^(s^) successfully.
echo.
exit /b 0

:VerifyFailed
echo.
pause
exit /b 1

:VerifyOne
if not exist "%TARGET_DIR%\%~1" (
    echo [ERROR] Missing required file in game folder: %~1
    exit /b 1
)
fc /b "%SCRIPT_DIR%\%~1" "%TARGET_DIR%\%~1" >nul
if errorlevel 2 (
    echo [ERROR] Could not verify file: %~1
    exit /b 1
)
if errorlevel 1 (
    echo [ERROR] Installed file does not match this patch: %~1
    exit /b 1
)
set /a VERIFY_COUNT+=1
exit /b 0


:CompareAgainstOriginal
echo [3/5] Comparing installed files to Original baseline...
if not exist "%SCRIPT_DIR%\Original\*.dll" (
    echo       Original baseline folder not found. Skipping comparison.
    echo.
    exit /b 0
)
set /a SAME_COUNT=0
set /a DIFFERENT_COUNT=0
set /a ABSENT_COUNT=0
for %%F in ("%SCRIPT_DIR%\Original\*.dll") do call :CompareOne "%%~fF"
echo       Different from Original: %DIFFERENT_COUNT%
echo       Same as Original:        %SAME_COUNT%
echo       Missing vs Original:     %ABSENT_COUNT%
echo.
exit /b 0

:CompareOne
set "CMPNAME=%~nx1"
if not exist "%TARGET_DIR%\%CMPNAME%" (
    set /a ABSENT_COUNT+=1
    if "%DEBUG_MODE%"=="1" echo       MISSING: %CMPNAME%
    exit /b 0
)
fc /b "%~1" "%TARGET_DIR%\%CMPNAME%" >nul
if errorlevel 2 (
    set /a ABSENT_COUNT+=1
    if "%DEBUG_MODE%"=="1" echo       MISSING: %CMPNAME% ^(compare error^)
    exit /b 0
)
if errorlevel 1 (
    set /a DIFFERENT_COUNT+=1
    if "%DEBUG_MODE%"=="1" echo       DIFFERENT: %CMPNAME%
    exit /b 0
)
set /a SAME_COUNT+=1
if "%DEBUG_MODE%"=="1" echo       SAME: %CMPNAME%
exit /b 0


:WriteInstallMarker
echo [4/5] Writing patch version marker...
(
    echo OIS Community Patch
    echo Version=%PATCH_VERSION%
    echo Files=%PAYLOAD_COUNT%
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


rem ------------------------------------------------------------ firewall
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


rem The netsh commands are written to a temp script instead of being escaped
rem through cmd -> powershell -> Start-Process -> cmd. That chain was the
rem single most fragile part of the old file.
:ApplyFirewall
set "FW_SCRIPT=%TEMP%\ois_firewall_%RANDOM%.cmd"
(
    echo @echo off
    echo netsh advfirewall firewall delete rule name="OIS_Client_Block_Inbound" ^>nul 2^>^&1
    echo netsh advfirewall firewall delete rule name="OIS_Server_Block_Inbound" ^>nul 2^>^&1
    echo netsh advfirewall firewall add rule name="OIS_Client_Block_Inbound" description="Community Patch: blocks inbound connections to secure legacy libwebsockets." dir=in action=block program="%TARGET_DIR%\ois.exe" enable=yes profile=any edge=no ^>nul
    echo netsh advfirewall firewall add rule name="OIS_Server_Block_Inbound" description="Community Patch: blocks inbound connections to secure legacy libwebsockets." dir=in action=block program="%TARGET_DIR%\ois_server.exe" enable=yes profile=any edge=no ^>nul
    echo exit /b 0
) > "%FW_SCRIPT%"

echo.
echo Windows may show an Administrator permission prompt.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Start-Process -FilePath '%FW_SCRIPT%' -Verb RunAs -Wait -WindowStyle Hidden" >nul 2>&1
del /F /Q "%FW_SCRIPT%" >nul 2>&1

netsh advfirewall firewall show rule name="OIS_Client_Block_Inbound" >nul 2>&1
if errorlevel 1 exit /b 1
netsh advfirewall firewall show rule name="OIS_Server_Block_Inbound" >nul 2>&1
if errorlevel 1 exit /b 1
exit /b 0


rem -------------------------------------------------------- update check
:OfferUpdateCheck
choice /C YN /M "Check online for a newer patch package?"
if errorlevel 2 (
    echo.
    exit /b 0
)
echo.
echo Checking for updates...

set "TMP_VER=%TEMP%\ois_remote_version_%RANDOM%.txt"
call :Download "%VERSION_URL%" "%TMP_VER%" quiet
if errorlevel 1 (
    echo [WARNING] Could not reach the update server. Continuing with the local package.
    echo.
    exit /b 0
)

set "REMOTE_VERSION="
for /f "usebackq delims=" %%V in ("%TMP_VER%") do (
    if not defined REMOTE_VERSION set "REMOTE_VERSION=%%V"
)
del /F /Q "%TMP_VER%" >nul 2>&1
if not defined REMOTE_VERSION (
    echo [WARNING] Update server returned an empty version. Continuing.
    echo.
    exit /b 0
)
call :NormalizeVersion REMOTE_VERSION

if /I "%REMOTE_VERSION%"=="%PATCH_VERSION%" (
    echo You already have the latest patch package ^(%PATCH_VERSION%^).
    echo.
    exit /b 0
)

echo A newer patch package is available: %REMOTE_VERSION%
echo You currently have:                 %PATCH_VERSION%
echo.
choice /C YN /M "Download it now?"
if errorlevel 2 (
    echo.
    exit /b 0
)

set "DL_DIR=%SCRIPT_DIR%\Downloads"
set "ZIP_PATH=%DL_DIR%\%REPO_NAME%-%REMOTE_VERSION%.zip"
set "EXTRACT_DIR=%DL_DIR%\%REPO_NAME%-%REMOTE_VERSION%"
set "NEW_SCRIPT=%EXTRACT_DIR%\%REPO_NAME%-%REPO_BRANCH%\Patch_OIS.bat"
if not exist "%DL_DIR%" md "%DL_DIR%" >nul 2>&1

if exist "%ZIP_PATH%" (
    echo Using previously downloaded package.
) else (
    echo Downloading %REMOTE_VERSION% ...
    call :Download "%ZIP_URL%" "%ZIP_PATH%" progress
)
if not exist "%ZIP_PATH%" (
    echo.
    echo [WARNING] Download failed. Continuing with the local package.
    echo.
    exit /b 0
)

echo Extracting...
if exist "%EXTRACT_DIR%" rd /S /Q "%EXTRACT_DIR%" >nul 2>&1
md "%EXTRACT_DIR%" >nul 2>&1
call :Extract "%ZIP_PATH%" "%EXTRACT_DIR%"

if not exist "%NEW_SCRIPT%" (
    echo.
    echo New package saved to: "%DL_DIR%"
    echo Could not locate Patch_OIS.bat inside it - please extract it manually.
    echo.
    choice /C YN /M "Continue installing the current package anyway?"
    if errorlevel 2 exit /b 2
    exit /b 0
)

echo.
echo New patch package ready: "%EXTRACT_DIR%"
echo.
choice /C YN /M "Run the newly downloaded installer instead?"
if errorlevel 2 (
    echo.
    echo Continuing with the current package.
    echo.
    exit /b 0
)
start "OIS Community Patch" /D "%EXTRACT_DIR%\%REPO_NAME%-%REPO_BRANCH%" "%NEW_SCRIPT%"
exit /b 2


:UpdateDownloadedExit
echo.
echo Setup handed off to the newly downloaded package.
echo.
pause
exit /b 0


rem ---------------------------------------------------------- networking
rem %1 = url   %2 = output path   %3 = quiet ^| progress
rem curl.exe ships with Windows 10 1803+ and is dramatically faster than
rem Invoke-WebRequest. The PowerShell fallback uses WebClient (streamed)
rem with the progress bar disabled, which is the other big IWR bottleneck.
:Download
if exist "%~2" del /F /Q "%~2" >nul 2>&1
if "%HAVE_CURL%"=="1" goto :Download_Curl
call :PSDownload "%~1" "%~2"
goto :Download_Check

:Download_Curl
if /I "%~3"=="quiet" (
    curl.exe -sS -L --fail --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 60 -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "%~2" "%~1"
) else (
    curl.exe -L --fail --retry 2 --retry-delay 1 --connect-timeout 10 --progress-bar -o "%~2" "%~1"
)

:Download_Check
if not exist "%~2" exit /b 1
for %%S in ("%~2") do (
    if "%%~zS"=="0" (
        del /F /Q "%~2" >nul 2>&1
        exit /b 1
    )
)
exit /b 0

:PSDownload
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11; $c=New-Object Net.WebClient; $c.Headers.Add('User-Agent','OIS-Update-Patcher'); try { $c.DownloadFile('%~1','%~2') } catch { exit 1 }" >nul 2>&1
exit /b


rem tar.exe (bsdtar) ships with Windows 10 1803+ and unpacks zips far faster
rem than Expand-Archive, which is single-file-at-a-time COM under the hood.
:Extract
if "%HAVE_TAR%"=="1" (
    tar.exe -xf "%~1" -C "%~2" >nul 2>&1
    if not errorlevel 1 exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory('%~1','%~2')" >nul 2>&1
exit /b 0


rem ------------------------------------------------------------- helpers
rem Strips a UTF-8 BOM, leading junk and trailing spaces from a version
rem string. If the result would be empty (e.g. "unknown") the original is
rem restored.
:NormalizeVersion
call set "NV=%%%~1%%"
set "NV_ORIG=%NV%"
:nv_head
if not defined NV goto :nv_restore
echo(%NV:~0,1%| findstr /R "^[0-9]" >nul
if not errorlevel 1 goto :nv_tail
set "NV=%NV:~1%"
goto :nv_head
:nv_tail
if not defined NV goto :nv_restore
if "%NV:~-1%"==" " (
    set "NV=%NV:~0,-1%"
    goto :nv_tail
)
set "%~1=%NV%"
exit /b 0
:nv_restore
set "%~1=%NV_ORIG%"
exit /b 0


rem Strips surrounding quotes, leading spaces and a trailing backslash.
:NormalizePath
call set "NP=%%%~1%%"
if not defined NP exit /b 0
for /f "tokens=* delims= " %%A in ("%NP%") do set "NP=%%~A"
if not defined NP exit /b 0
if "%NP:~-1%"=="\" set "NP=%NP:~0,-1%"
set "%~1=%NP%"
exit /b 0


:Finish
echo ===================================================
echo   SUCCESS! Objects in Space is ready to play.
echo.
echo Installed patch version: %PATCH_VERSION%
echo Files installed:         %PAYLOAD_COUNT%
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
