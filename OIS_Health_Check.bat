@echo off
setlocal EnableExtensions DisableDelayedExpansion
title OIS Community Patch - Integrity Check

rem =====================================================================
rem  OIS_Health_Check.bat  [options] [game folder]
rem
rem    -repair        re-copy any file that no longer matches
rem    -quiet         no console output, log only (for scheduled runs)
rem    -install-task  copy the package to ProgramData and register the
rem                   scheduled task, then exit
rem    -remove-task   unregister the scheduled task, then exit
rem
rem  Reads OIS_Update.manifest.txt from the game folder and compares the
rem  SHA256 of every listed file. Detects Steam "Verify integrity of game
rem  files", which silently restores the vanilla DLLs.
rem
rem  This script NEVER touches the network. It repairs only from the local
rem  package folder. Downloading is Patch_OIS.bat's job and stays under
rem  human control.
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "TASK_NAME=OIS Community Patch Integrity"
set "INSTALL_ROOT=%ProgramData%\OIS-Update"
set "LOG_FILE=%INSTALL_ROOT%\health.log"
set "GAME_MANIFEST_NAME=OIS_Update.manifest.txt"

set "DO_REPAIR=0"
set "QUIET=0"
set "DO_INSTALL_TASK=0"
set "DO_REMOVE_TASK=0"
set "TARGET_DIR="

call :ParseArgs %*
if "%DO_REMOVE_TASK%"=="1" goto :RemoveTask
if "%DO_INSTALL_TASK%"=="1" goto :InstallTask

if not defined TARGET_DIR call :FindTarget
if not defined TARGET_DIR (
    call :Say "[ERROR] Could not locate the Objects in Space folder."
    call :Log  "ERROR no game folder found"
    if "%QUIET%"=="0" pause
    exit /b 1
)

set "GAME_MANIFEST=%TARGET_DIR%\%GAME_MANIFEST_NAME%"
if not exist "%GAME_MANIFEST%" (
    call :Say "[ERROR] No installed manifest found. Run Patch_OIS.bat first."
    call :Log  "ERROR no installed manifest in %TARGET_DIR%"
    if "%QUIET%"=="0" pause
    exit /b 1
)

set /a OK_COUNT=0
set /a DRIFT_COUNT=0
set /a FIXED_COUNT=0
set /a UNFIXED_COUNT=0

call :Say "Checking %TARGET_DIR% ..."
for /f "usebackq eol=# tokens=1,* delims= " %%A in ("%GAME_MANIFEST%") do call :CheckOne "%%~B" "%%~A"

call :Say ""
call :Say "  matching: %OK_COUNT%   drifted: %DRIFT_COUNT%   repaired: %FIXED_COUNT%   unrepaired: %UNFIXED_COUNT%"

if %DRIFT_COUNT% EQU 0 (
    call :Log "OK all %OK_COUNT% files match"
    if "%QUIET%"=="0" (
        echo.
        echo Patch is intact.
        echo.
        pause
    )
    exit /b 0
)

call :Log "DRIFT %DRIFT_COUNT% file(s) changed, repaired %FIXED_COUNT%, unrepaired %UNFIXED_COUNT%"
if "%DO_REPAIR%"=="0" (
    call :Say ""
    call :Say "The patch is no longer intact. This usually means Steam verified"
    call :Say "the game files and restored the vanilla DLLs."
    call :Say "Run Patch_OIS.bat, or this script with -repair, to re-apply it."
    if "%QUIET%"=="0" (
        echo.
        pause
    )
    exit /b 2
)
if %UNFIXED_COUNT% GTR 0 (
    if "%QUIET%"=="0" (
        echo.
        pause
    )
    exit /b 2
)
if "%QUIET%"=="0" (
    echo.
    echo Patch re-applied.
    echo.
    pause
)
exit /b 0


rem ---------------------------------------------------------------------
:ParseArgs
if "%~1"=="" exit /b 0
if /I "%~1"=="-repair"       ( set "DO_REPAIR=1"       & shift & goto :ParseArgs )
if /I "%~1"=="-quiet"        ( set "QUIET=1"           & shift & goto :ParseArgs )
if /I "%~1"=="-install-task" ( set "DO_INSTALL_TASK=1" & shift & goto :ParseArgs )
if /I "%~1"=="-remove-task"  ( set "DO_REMOVE_TASK=1"  & shift & goto :ParseArgs )
set "TARGET_DIR=%~1"
if defined TARGET_DIR if "%TARGET_DIR:~-1%"=="\" set "TARGET_DIR=%TARGET_DIR:~0,-1%"
shift
goto :ParseArgs


:CheckOne
rem %1 = filename   %2 = expected sha256
if "%~1"=="" exit /b 0
if not exist "%TARGET_DIR%\%~1" (
    set /a DRIFT_COUNT+=1
    call :Say "  MISSING  %~1"
    call :Repair "%~1"
    exit /b 0
)
call :HashFile "%TARGET_DIR%\%~1"
if errorlevel 1 (
    set /a DRIFT_COUNT+=1
    call :Say "  UNREADABLE  %~1"
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
if /I "%HASH%"=="%~2" (
    set /a OK_COUNT+=1
    exit /b 0
)
set /a DRIFT_COUNT+=1
call :Say "  CHANGED  %~1"
call :Repair "%~1"
exit /b 0


:Repair
if "%DO_REPAIR%"=="0" (
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
if not exist "%SCRIPT_DIR%\%~1" (
    call :Say "           no local copy of %~1 to repair from"
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
copy /Y "%SCRIPT_DIR%\%~1" "%TARGET_DIR%\%~1" >nul 2>&1
if errorlevel 1 (
    call :Say "           repair failed for %~1 (permissions?)"
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
call :Say "           repaired %~1"
set /a FIXED_COUNT+=1
exit /b 0


:FindTarget
for %%I in ("%ProgramFiles(x86)%\Steam" "%ProgramFiles%\Steam" "%USERPROFILE%\Steam" "%SystemDrive%\Steam") do (
    if exist "%%~I\steamapps\common\Objects in Space\ois.exe" (
        set "TARGET_DIR=%%~I\steamapps\common\Objects in Space"
        exit /b 0
    )
)
for %%K in ("HKCU\Software\Valve\Steam" "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" "HKLM\SOFTWARE\Valve\Steam") do (
    for /f "tokens=2,*" %%A in ('reg query "%%~K" /v InstallPath 2^>nul ^| findstr /R /C:"InstallPath"') do (
        if exist "%%~B\steamapps\common\Objects in Space\ois.exe" (
            set "TARGET_DIR=%%~B\steamapps\common\Objects in Space"
            exit /b 0
        )
    )
)
exit /b 0


rem ------------------------------------------------------ task management
rem The task runs as SYSTEM so it needs no UAC prompt and shows no console
rem window. That is also, honestly, the same shape as a persistence
rem mechanism, so it is opt-in, it never downloads anything, and it repairs
rem only from the copy under ProgramData.
:InstallTask
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Administrator rights are required to create the scheduled task.
    echo Right-click this file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

if not defined TARGET_DIR call :FindTarget
if not defined TARGET_DIR (
    echo [ERROR] Could not locate the game folder. Pass it as an argument:
    echo   OIS_Health_Check.bat -install-task "D:\SteamLibrary\steamapps\common\Objects in Space"
    echo.
    pause
    exit /b 1
)

echo Copying the patch package to "%INSTALL_ROOT%" ...
if not exist "%INSTALL_ROOT%" md "%INSTALL_ROOT%" >nul 2>&1
copy /Y "%SCRIPT_DIR%\*.dll" "%INSTALL_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\manifest.txt" "%INSTALL_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\VERSION.txt" "%INSTALL_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\OIS_Health_Check.bat" "%INSTALL_ROOT%\" >nul 2>&1

set "TASK_CMD=%INSTALL_ROOT%\OIS_Health_Check.bat"
schtasks /Create /TN "%TASK_NAME%" /TR "\"%TASK_CMD%\" -repair -quiet \"%TARGET_DIR%\"" /SC ONLOGON /RU SYSTEM /RL HIGHEST /F >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create the scheduled task.
    echo.
    pause
    exit /b 1
)

echo.
echo Scheduled task created: "%TASK_NAME%"
echo   runs   : at every logon, as SYSTEM, no window
echo   package: "%INSTALL_ROOT%"
echo   log    : "%LOG_FILE%"
echo.
echo To also run it daily at noon:
echo   schtasks /Create /TN "%TASK_NAME% Daily" /TR "\"%TASK_CMD%\" -repair -quiet" /SC DAILY /ST 12:00 /RU SYSTEM /RL HIGHEST /F
echo.
echo To remove it:  OIS_Health_Check.bat -remove-task
echo.
pause
exit /b 0


:RemoveTask
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Administrator rights are required to remove the scheduled task.
    echo.
    pause
    exit /b 1
)
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
schtasks /Delete /TN "%TASK_NAME% Daily" /F >nul 2>&1
echo Scheduled task removed. The copy under "%INSTALL_ROOT%" was left in place.
echo.
pause
exit /b 0


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

:Say
if "%QUIET%"=="1" exit /b 0
echo %~1
exit /b 0

:Log
if not exist "%INSTALL_ROOT%" md "%INSTALL_ROOT%" >nul 2>&1
>> "%LOG_FILE%" echo %DATE% %TIME%  %~1
exit /b 0
