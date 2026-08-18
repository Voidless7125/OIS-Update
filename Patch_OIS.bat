@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Objects in Space - Community Patch

rem =====================================================================
rem  Objects in Space: Community Patch Setup
rem
rem  Optional argument: -debug       shows per-file compare details
rem  Optional argument: -uninstall   restores pre-patch files from Backup\
rem
rem  MAINTAINER NOTE: this file MUST be saved with Windows (CRLF) line
rem  endings. Batch label lookup is unreliable in LF-only files. Add this
rem  to .gitattributes so GitHub never converts it:
rem      *.bat text eol=crlf
rem      *.cmd text eol=crlf
rem =====================================================================

set "REPO_OWNER=Voidless7125"
set "REPO_NAME=OIS-Update"
set "REPO_BRANCH=dev"
set "RAW_BASE=https://raw.githubusercontent.com/%REPO_OWNER%/%REPO_NAME%/%REPO_BRANCH%"

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "MANIFEST=%SCRIPT_DIR%\manifest.txt"
set "BACKUP_DIR=%SCRIPT_DIR%\Backup"
set "RETIRED_DIR=%SCRIPT_DIR%\Retired"
set "GAME_MANIFEST_NAME=OIS_Update.manifest.txt"
set "PATCH_VERSION="
set "DEBUG_MODE=0"
set "TARGET_OVERRIDE="
set "PAYLOAD_LIST="
set "PAYLOAD_COUNT=0"
set "UNINSTALL_MODE=0"
set "HAVE_CURL=0"
where curl.exe >nul 2>&1 && set "HAVE_CURL=1"

if exist "%SCRIPT_DIR%\Patch_OIS.bat.new" goto :SelfUpdateSwap

call :ParseArgs %* || goto :Fail
call :LoadPatchVersion
if "%UNINSTALL_MODE%"=="1" goto :DoUninstall
call :ShowChangelog
call :OfferUpdateCheck
if errorlevel 2 goto :SelfUpdateSwap
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
call :OfferRepairShortcut
call :Finish
exit /b 0


rem ---------------------------------------------------------------- UI
:ParseArgs
if "%~1"=="" exit /b 0
if /I "%~1"=="-debug"  ( set "DEBUG_MODE=1" & shift & goto :ParseArgs )
if /I "%~1"=="--debug" ( set "DEBUG_MODE=1" & shift & goto :ParseArgs )
if /I "%~1"=="/debug"  ( set "DEBUG_MODE=1" & shift & goto :ParseArgs )
if /I "%~1"=="-uninstall"  ( set "UNINSTALL_MODE=1" & shift & goto :ParseArgs )
if /I "%~1"=="--uninstall" ( set "UNINSTALL_MODE=1" & shift & goto :ParseArgs )
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
exit /b 0


rem Renders everything after line 1 of VERSION.txt. Lines beginning with #
rem are maintainer notes and stay hidden. FOR-variable expansion happens
rem after the parser has finished, so ^&, ^| and brackets inside the
rem changelog text are printed literally and cannot break anything.
:ShowChangelog
if not exist "%SCRIPT_DIR%\VERSION.txt" (
    echo   Objects in Space: Community Patch Setup
    echo   Patch package version: %PATCH_VERSION%
    echo.
    exit /b 0
)
echo.
for /f "usebackq skip=1 eol=# tokens=* delims=" %%L in ("%SCRIPT_DIR%\VERSION.txt") do echo  %%L
echo.
exit /b 0


rem ------------------------------------------------------- payload build
:BuildPayload
echo Loading patch file list...
set "PAYLOAD_LIST="
set /a PAYLOAD_COUNT=0
set /a MISSING_COUNT=0
set /a BADHASH_COUNT=0

if not exist "%MANIFEST%" (
    echo [ERROR] manifest.txt is missing from the patch folder.
    echo Run Make_Manifest.bat in the patch folder, or re-download the package.
    echo.
    pause
    exit /b 1
)

for /f "usebackq eol=# tokens=1,2,* delims= " %%A in ("%MANIFEST%") do (
    if /I "%%~A"=="game" call :CheckPackageFile "%%~C" "%%~B"
)

if %PAYLOAD_COUNT% EQU 0 (
    echo [ERROR] manifest.txt lists no game files.
    echo.
    pause
    exit /b 1
)
if %MISSING_COUNT% GTR 0 goto :PayloadBad
if %BADHASH_COUNT% GTR 0 goto :PayloadBad
echo Validated %PAYLOAD_COUNT% patch file^(s^) against manifest.txt.
echo.
exit /b 0

:PayloadBad
echo.
echo [ERROR] The patch package is damaged or incomplete.
echo   missing: %MISSING_COUNT%    wrong hash: %BADHASH_COUNT%
echo Re-run this script and accept the update check, or re-download the package.
echo.
pause
exit /b 1

:CheckPackageFile
if not exist "%SCRIPT_DIR%\%~1" (
    echo [ERROR] Listed in manifest but missing: %~1
    set /a MISSING_COUNT+=1
    exit /b 0
)
call :HashFile "%SCRIPT_DIR%\%~1"
if errorlevel 1 (
    echo [ERROR] Could not hash: %~1
    set /a MISSING_COUNT+=1
    exit /b 0
)
if /I not "%HASH%"=="%~2" (
    echo [ERROR] Hash mismatch in package: %~1
    set /a BADHASH_COUNT+=1
    exit /b 0
)
set PAYLOAD_LIST=%PAYLOAD_LIST% "%~1"
set /a PAYLOAD_COUNT+=1
exit /b 0


rem ------------------------------------------------------ target folder
rem Nothing here exits or jumps out of a FOR body. Loops guard themselves
rem with "if not defined TARGET_DIR", which is evaluated at run time, so
rem the parser's file position is never disturbed mid-loop.
:DetectTarget
set "TARGET_DIR="
if not "%~1"=="" (
    set "TARGET_DIR=%~1"
    call :NormalizePath TARGET_DIR
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
    if not defined TARGET_DIR call :ScanSteamRoot "%%~I"
)
if defined TARGET_DIR exit /b 0

for %%K in ("HKCU\Software\Valve\Steam" "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" "HKLM\SOFTWARE\Valve\Steam") do (
    for /f "tokens=2,*" %%A in ('reg query "%%~K" /v InstallPath 2^>nul ^| findstr /R /C:"InstallPath"') do (
        if not defined TARGET_DIR call :ScanSteamRoot "%%~B"
    )
)
if defined TARGET_DIR exit /b 0

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


:ScanSteamRoot
if exist "%~1\steamapps\common\Objects in Space\ois.exe" (
    set "TARGET_DIR=%~1\steamapps\common\Objects in Space"
    exit /b 0
)
if exist "%~1\steamapps\common\Objects in Space\ois_server.exe" (
    set "TARGET_DIR=%~1\steamapps\common\Objects in Space"
    exit /b 0
)
if not exist "%~1\steamapps\libraryfolders.vdf" exit /b 1
for /f "usebackq tokens=2 delims=	 " %%P in (`findstr /I /C:"\"path\"" "%~1\steamapps\libraryfolders.vdf"`) do (
    if not defined TARGET_DIR call :TryLibrary %%P
)
if defined TARGET_DIR exit /b 0
exit /b 1

:TryLibrary
set "LIB=%~1"
if not defined LIB exit /b 1
rem libraryfolders.vdf escapes backslashes, so D:\\SteamLibrary comes back doubled.
set "LIB=%LIB:\\=\%"
call :IsValidGameDir "%LIB%\steamapps\common\Objects in Space" >nul 2>&1
if errorlevel 1 exit /b 1
set "TARGET_DIR=%LIB%\steamapps\common\Objects in Space"
exit /b 0

:IsValidGameDir
if exist "%~1\ois.exe" exit /b 0
if exist "%~1\ois_server.exe" exit /b 0
exit /b 1


:ShowInstalledVersion
if not exist "%TARGET_DIR%\OIS_Update.version.txt" (
    echo No existing patch marker found in game folder.
    echo.
    exit /b 0
)
echo Existing patch marker found in game folder:
for /f "usebackq delims=" %%L in ("%TARGET_DIR%\OIS_Update.version.txt") do echo   %%L
echo.
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
if not exist "%BACKUP_DIR%" md "%BACKUP_DIR%" >nul 2>&1
call :RestoreDelisted
call :RemoveObsolete
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


:RestoreDelisted
if not exist "%TARGET_DIR%\%GAME_MANIFEST_NAME%" exit /b 0
for /f "usebackq eol=# tokens=1,* delims= " %%A in ("%TARGET_DIR%\%GAME_MANIFEST_NAME%") do call :CheckDelisted "%%~B"
exit /b 0

:CheckDelisted
if "%~1"=="" exit /b 0
findstr /I /E /C:" %~1" "%MANIFEST%" >nul && exit /b 0
if not exist "%TARGET_DIR%\%~1" exit /b 0
if exist "%SCRIPT_DIR%\Original\%~1" (
    echo       Restoring stock %~1 ^(no longer patched^)...
    if not exist "%BACKUP_DIR%\%~1" copy /Y "%TARGET_DIR%\%~1" "%BACKUP_DIR%\%~1" >nul 2>&1
    copy /Y "%SCRIPT_DIR%\Original\%~1" "%TARGET_DIR%\%~1" >nul 2>&1
) else (
    echo       Note: %~1 is no longer patched; leaving the existing copy alone.
)
exit /b 0

:RemoveObsolete
if not exist "%SCRIPT_DIR%\obsolete.txt" exit /b 0
for /f "usebackq eol=# tokens=* delims=" %%F in ("%SCRIPT_DIR%\obsolete.txt") do call :DeleteObsolete "%%~F"
exit /b 0

:DeleteObsolete
if "%~1"=="" exit /b 0
if not exist "%TARGET_DIR%\%~1" exit /b 0
echo       Removing obsolete %~1...
if not exist "%BACKUP_DIR%\%~1" copy /Y "%TARGET_DIR%\%~1" "%BACKUP_DIR%\%~1" >nul 2>&1
del /F /Q "%TARGET_DIR%\%~1" >nul 2>&1
exit /b 0

:UnblockFiles
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Get-ChildItem -LiteralPath '%TARGET_DIR%' -Filter '*.dll' -File | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
exit /b 0


:VerifyRuntimeFiles
echo [2/5] Verifying installed files by SHA256...
set /a VERIFY_COUNT=0
set /a VERIFY_FAIL=0
for /f "usebackq eol=# tokens=1,2,* delims= " %%A in ("%MANIFEST%") do (
    if /I "%%~A"=="game" call :VerifyOne "%%~C" "%%~B"
)
if %VERIFY_FAIL% GTR 0 (
    echo.
    echo [ERROR] %VERIFY_FAIL% file^(s^) in the game folder do not match the patch.
    echo.
    pause
    exit /b 1
)
echo       Verified %VERIFY_COUNT% file^(s^) successfully.
echo.
exit /b 0

:VerifyOne
if not exist "%TARGET_DIR%\%~1" (
    echo [ERROR] Missing in game folder: %~1
    set /a VERIFY_FAIL+=1
    exit /b 0
)
call :HashFile "%TARGET_DIR%\%~1"
if errorlevel 1 (
    echo [ERROR] Could not hash: %~1
    set /a VERIFY_FAIL+=1
    exit /b 0
)
if /I not "%HASH%"=="%~2" (
    echo [ERROR] Installed file does not match this patch: %~1
    set /a VERIFY_FAIL+=1
    exit /b 0
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


rem Written line by line rather than as one ( ... ) ^> file block. A block
rem is parsed as a single command, so an unquoted path containing round
rem brackets - "OIS-Update-dev (1)" from a second browser download, or
rem anything under Program Files (x86) - closes the block early and throws
rem "was unexpected at this time". Sequential redirects have no such issue.
:WriteInstallMarker
echo [4/5] Writing patch marker and game-folder manifest...
set "MARKER=%TARGET_DIR%\OIS_Update.version.txt"
> "%MARKER%" echo OIS Community Patch
if errorlevel 1 (
    echo [ERROR] Could not write version marker to game folder.
    echo.
    pause
    exit /b 1
)
>>"%MARKER%" echo Version=%PATCH_VERSION%
>>"%MARKER%" echo Files=%PAYLOAD_COUNT%
>>"%MARKER%" echo Installed=%DATE% %TIME%
>>"%MARKER%" echo Source=%SCRIPT_DIR%
>>"%MARKER%" echo Script=Patch_OIS.bat

set "GM=%TARGET_DIR%\%GAME_MANIFEST_NAME%"
> "%GM%" echo # OIS Community Patch installed manifest
>>"%GM%" echo # Version=%PATCH_VERSION%
>>"%GM%" echo # Installed=%DATE% %TIME%
>>"%GM%" echo # Package=%SCRIPT_DIR%
>>"%GM%" echo # Format: ^<sha256^> ^<filename^>
for /f "usebackq eol=# tokens=1,2,* delims= " %%A in ("%MANIFEST%") do (
    if /I "%%~A"=="game" >>"%GM%" echo %%~B %%~C
)
echo       Wrote: "%GM%"
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

:ApplyFirewall
set "FW=%TEMP%\ois_firewall_%RANDOM%.cmd"
set "FWDESC=Community Patch: blocks inbound connections to secure legacy libwebsockets."
> "%FW%" echo @echo off
>>"%FW%" echo netsh advfirewall firewall delete rule name="OIS_Client_Block_Inbound" ^>nul 2^>^&1
>>"%FW%" echo netsh advfirewall firewall delete rule name="OIS_Server_Block_Inbound" ^>nul 2^>^&1
>>"%FW%" echo netsh advfirewall firewall add rule name="OIS_Client_Block_Inbound" description="%FWDESC%" dir=in action=block program="%TARGET_DIR%\ois.exe" enable=yes profile=any edge=no ^>nul
>>"%FW%" echo netsh advfirewall firewall add rule name="OIS_Server_Block_Inbound" description="%FWDESC%" dir=in action=block program="%TARGET_DIR%\ois_server.exe" enable=yes profile=any edge=no ^>nul
>>"%FW%" echo exit /b 0
echo.
echo Windows may show an Administrator permission prompt.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Start-Process -FilePath '%FW%' -Verb RunAs -Wait -WindowStyle Hidden" >nul 2>&1
del /F /Q "%FW%" >nul 2>&1
netsh advfirewall firewall show rule name="OIS_Client_Block_Inbound" >nul 2>&1
if errorlevel 1 exit /b 1
netsh advfirewall firewall show rule name="OIS_Server_Block_Inbound" >nul 2>&1
if errorlevel 1 exit /b 1
exit /b 0


:OfferRepairShortcut
if not exist "%SCRIPT_DIR%\OIS_Health_Check.bat" exit /b 0
echo Optional: repair shortcut
echo Steam's "Verify integrity of game files" will silently undo this patch.
echo A shortcut lets you put it back in one click if that ever happens.
echo.
choice /C YN /M "Create a 'Repair Objects in Space Patch' shortcut?"
if errorlevel 2 (
    echo.
    echo Skipped. You can create it later with:
    echo   OIS_Health_Check.bat -install-shortcut
    echo.
    exit /b 0
)
call "%SCRIPT_DIR%\OIS_Health_Check.bat" -install-shortcut "%TARGET_DIR%"
echo.
exit /b 0


rem -------------------------------------------------- incremental update
:OfferUpdateCheck
choice /C YN /M "Check online for a newer patch package?"
if errorlevel 2 (
    echo.
    exit /b 0
)
echo.
echo Checking for updates...

set "TMP_VER=%TEMP%\ois_remote_version_%RANDOM%.txt"
call :Download "%RAW_BASE%/VERSION.txt" "%TMP_VER%" quiet
if errorlevel 1 (
    echo [WARNING] Could not reach the update server. Continuing with the local package.
    echo.
    exit /b 0
)
set "REMOTE_VERSION="
for /f "usebackq delims=" %%V in ("%TMP_VER%") do (
    if not defined REMOTE_VERSION set "REMOTE_VERSION=%%V"
)
if not defined REMOTE_VERSION (
    del /F /Q "%TMP_VER%" >nul 2>&1
    echo [WARNING] Update server returned an empty version. Continuing.
    echo.
    exit /b 0
)
call :NormalizeVersion REMOTE_VERSION

if /I "%REMOTE_VERSION%"=="%PATCH_VERSION%" (
    del /F /Q "%TMP_VER%" >nul 2>&1
    echo You already have the latest patch package ^(%PATCH_VERSION%^).
    echo.
    exit /b 0
)

echo Newer package available: %REMOTE_VERSION%   ^(you have %PATCH_VERSION%^)
echo.
choice /C YN /M "Download the changed files now?"
if errorlevel 2 (
    del /F /Q "%TMP_VER%" >nul 2>&1
    echo.
    exit /b 0
)

set "TMP_MAN=%TEMP%\ois_remote_manifest_%RANDOM%.txt"
call :Download "%RAW_BASE%/manifest.txt" "%TMP_MAN%" quiet
if errorlevel 1 (
    del /F /Q "%TMP_VER%" >nul 2>&1
    echo [WARNING] Could not download the remote manifest. Continuing.
    echo.
    exit /b 0
)

set /a SYNC_OK=0
set /a SYNC_NEW=0
set /a SYNC_FAIL=0
set "SELF_UPDATED=0"
for /f "usebackq eol=# tokens=1,2,* delims= " %%A in ("%TMP_MAN%") do call :SyncFile "%%~C" "%%~B"

if %SYNC_FAIL% GTR 0 (
    del /F /Q "%TMP_VER%" >nul 2>&1
    del /F /Q "%TMP_MAN%" >nul 2>&1
    echo.
    echo [WARNING] %SYNC_FAIL% file^(s^) failed to download. Package left unchanged.
    echo.
    exit /b 0
)

if not exist "%RETIRED_DIR%" md "%RETIRED_DIR%" >nul 2>&1
for %%F in ("%SCRIPT_DIR%\*.dll") do call :RetireIfDropped "%%~nxF"

copy /Y "%TMP_MAN%" "%MANIFEST%" >nul
copy /Y "%TMP_VER%" "%SCRIPT_DIR%\VERSION.txt" >nul
del /F /Q "%TMP_VER%" >nul 2>&1
del /F /Q "%TMP_MAN%" >nul 2>&1

echo.
echo Update complete: %SYNC_NEW% file^(s^) downloaded, %SYNC_OK% already current.
set "PATCH_VERSION=%REMOTE_VERSION%"
echo Package is now version %PATCH_VERSION%.
echo.
if "%SELF_UPDATED%"=="1" (
    echo Patch_OIS.bat itself was updated. Restarting with the new version...
    exit /b 2
)
exit /b 0

:SyncFile
if "%~1"=="" exit /b 0
if exist "%SCRIPT_DIR%\%~1" (
    call :HashFile "%SCRIPT_DIR%\%~1"
    if not errorlevel 1 if /I "%HASH%"=="%~2" (
        set /a SYNC_OK+=1
        exit /b 0
    )
)
set "SYNC_DEST=%SCRIPT_DIR%\%~1"
if /I "%~1"=="Patch_OIS.bat" set "SYNC_DEST=%SCRIPT_DIR%\Patch_OIS.bat.new"
echo   downloading %~1 ...
call :Download "%RAW_BASE%/%~1" "%SYNC_DEST%" quiet
if errorlevel 1 (
    echo   [ERROR] download failed: %~1
    set /a SYNC_FAIL+=1
    exit /b 0
)
call :HashFile "%SYNC_DEST%"
if errorlevel 1 (
    set /a SYNC_FAIL+=1
    exit /b 0
)
if /I not "%HASH%"=="%~2" (
    echo   [ERROR] downloaded file failed its hash check: %~1
    del /F /Q "%SYNC_DEST%" >nul 2>&1
    set /a SYNC_FAIL+=1
    exit /b 0
)
if /I "%~1"=="Patch_OIS.bat" set "SELF_UPDATED=1"
set /a SYNC_NEW+=1
exit /b 0

:RetireIfDropped
findstr /I /E /C:" %~1" "%TMP_MAN%" >nul && exit /b 0
echo   retiring %~1 ^(no longer shipped^)...
move /Y "%SCRIPT_DIR%\%~1" "%RETIRED_DIR%\%~1" >nul 2>&1
exit /b 0


:SelfUpdateSwap
if not exist "%SCRIPT_DIR%\Patch_OIS.bat.new" (
    echo.
    echo Update finished. Please run Patch_OIS.bat again.
    echo.
    pause
    exit /b 0
)
set "SWAP=%TEMP%\ois_swap_%RANDOM%.cmd"
> "%SWAP%" echo @echo off
>>"%SWAP%" echo ping -n 3 127.0.0.1 ^>nul
>>"%SWAP%" echo move /Y "%SCRIPT_DIR%\Patch_OIS.bat.new" "%SCRIPT_DIR%\Patch_OIS.bat" ^>nul
>>"%SWAP%" echo start "Objects in Space - Community Patch" /D "%SCRIPT_DIR%" "%SCRIPT_DIR%\Patch_OIS.bat"
>>"%SWAP%" echo del /F /Q "%%~f0"
echo.
echo Applying updated installer and restarting...
start "" /MIN "%SWAP%"
exit


rem ---------------------------------------------------------- networking
:Download
if exist "%~2" del /F /Q "%~2" >nul 2>&1
if "%HAVE_CURL%"=="1" goto :Download_Curl
call :PSDownload "%~1" "%~2"
goto :Download_Check

:Download_Curl
if /I "%~3"=="quiet" (
    curl.exe -sS -L --fail --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 120 -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "%~2" "%~1"
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $c=New-Object Net.WebClient; $c.Headers.Add('User-Agent','OIS-Update-Patcher'); $c.Headers.Add('Cache-Control','no-cache'); try { $c.DownloadFile('%~1','%~2') } catch { exit 1 }" >nul 2>&1
exit /b


rem ------------------------------------------------------------- helpers
:HashFile
set "HASH="
for /f "usebackq skip=1 delims=" %%H in (`certutil -hashfile "%~1" SHA256 2^>nul`) do (
    if not defined HASH set "HASH=%%H"
)
if not defined HASH exit /b 1
set "HASH=%HASH: =%"
if not defined HASH exit /b 1
exit /b 0

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

:NormalizePath
call set "NP=%%%~1%%"
if not defined NP exit /b 0
for /f "tokens=* delims= " %%A in ("%NP%") do set "NP=%%~A"
if not defined NP exit /b 0
if "%NP:~-1%"=="\" set "NP=%NP:~0,-1%"
set "%~1=%NP%"
exit /b 0


:Finish
echo ===============================================================
echo   SUCCESS - Objects in Space is ready to play.
echo.
echo   Installed patch version: %PATCH_VERSION%
echo   Files installed:         %PAYLOAD_COUNT%
echo.
echo   Steam's "Verify integrity of game files" will revert this patch.
echo   Use the "Repair Objects in Space Patch" shortcut to put it back.
echo.
echo   Problems? https://steamcommunity.com/app/824070/discussions/0/573795849686060451/
echo ===============================================================
echo.
pause
exit /b 0

rem ------------------------------------------------------------ uninstall
rem Backup\ holds, per filename, the FIRST copy of that file this package
rem ever overwrote - true pre-patch state, not "last patched version" -
rem see :CopyOne, :RestoreDelisted and :DeleteObsolete, which all write to
rem it on first touch only. Restoring means copying everything in Backup\
rem back over the game folder and removing the two patch marker files, so
rem a subsequent Patch_OIS.bat run treats the folder as never patched.
:DoUninstall
call :DetectTarget "%TARGET_OVERRIDE%" || goto :Fail
call :ShowInstalledVersion

if not exist "%BACKUP_DIR%\*" (
    echo [ERROR] No Backup folder found next to this script:
    echo "%BACKUP_DIR%"
    echo.
    echo Nothing to restore from. Either the patch was never installed
    echo from this copy of the package, or the Backup folder was deleted.
    echo.
    pause
    exit /b 1
)

echo This will restore your pre-patch game files from:
echo   "%BACKUP_DIR%"
echo into:
echo   "%TARGET_DIR%"
echo.
choice /C YN /M "Restore original files now?"
if errorlevel 2 (
    echo.
    echo Uninstall canceled.
    echo.
    pause
    exit /b 0
)
call :EnsureGameClosed || goto :Fail

echo.
echo Restoring pre-patch files...
set /a RESTORE_COUNT=0
set /a RESTORE_FAIL=0
for %%F in ("%BACKUP_DIR%\*") do call :RestoreOne "%%~nxF"

del /F /Q "%TARGET_DIR%\OIS_Update.version.txt" >nul 2>&1
del /F /Q "%TARGET_DIR%\%GAME_MANIFEST_NAME%" >nul 2>&1

echo.
if %RESTORE_FAIL% GTR 0 (
    echo [WARNING] %RESTORE_FAIL% file^(s^) could not be restored.
    echo Restored %RESTORE_COUNT% file^(s^) successfully; the game folder
    echo may now be a mix of patched and stock files. Verifying files
    echo through Steam is the safest way to reach a clean state.
    echo.
) else (
    echo Restored %RESTORE_COUNT% file^(s^). Patch markers removed.
    echo Your game folder should now match its pre-patch state.
    echo.
)

call :OfferFirewallRemoval

echo ===============================================================
echo   UNINSTALL COMPLETE
echo ===============================================================
echo.
pause
exit /b 0

:RestoreOne
copy /Y "%BACKUP_DIR%\%~1" "%TARGET_DIR%\%~1" >nul 2>&1
if errorlevel 1 (
    echo   [ERROR] failed to restore %~1
    set /a RESTORE_FAIL+=1
    exit /b 0
)
echo   restored %~1
set /a RESTORE_COUNT+=1
exit /b 0

:OfferFirewallRemoval
netsh advfirewall firewall show rule name="OIS_Client_Block_Inbound" >nul 2>&1
if errorlevel 1 exit /b 0
echo.
choice /C YN /M "Also remove the firewall rules this patch created?"
if errorlevel 2 exit /b 0
set "FW=%TEMP%\ois_firewall_del_%RANDOM%.cmd"
> "%FW%" echo @echo off
>>"%FW%" echo netsh advfirewall firewall delete rule name="OIS_Client_Block_Inbound" ^>nul 2^>^&1
>>"%FW%" echo netsh advfirewall firewall delete rule name="OIS_Server_Block_Inbound" ^>nul 2^>^&1
>>"%FW%" echo exit /b 0
echo Windows may show an Administrator permission prompt.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Start-Process -FilePath '%FW%' -Verb RunAs -Wait -WindowStyle Hidden" >nul 2>&1
del /F /Q "%FW%" >nul 2>&1
echo Firewall rules removed.
exit /b 0


:Fail
echo.
echo Setup did not complete.
echo.
pause
exit /b 1