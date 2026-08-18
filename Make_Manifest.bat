@echo off
setlocal EnableExtensions DisableDelayedExpansion
title OIS Community Patch - Manifest Builder

rem =====================================================================
rem  Make_Manifest.bat
rem  Run this in the patch folder AFTER changing any DLL or bumping
rem  VERSION.txt, then commit manifest.txt alongside the files.
rem
rem  manifest.txt format (space delimited, # = comment):
rem      <scope> <sha256> <filename>
rem  scope game = installed into the game folder
rem  scope tool = package only (scripts, docs)
rem
rem  Everything downstream is driven by this file: what gets installed,
rem  what gets verified, what gets downloaded on update, and what gets
rem  retired when you stop shipping a DLL.
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "MANIFEST=%SCRIPT_DIR%\manifest.txt"
set "TMPFILE=%SCRIPT_DIR%\manifest.txt.tmp"
set "TOOL_FILES=Patch_OIS.bat OIS_Health_Check.bat Make_Manifest.bat VERSION.txt SECURITY.md README.md obsolete.txt"

set "PATCH_VERSION="
if exist "%SCRIPT_DIR%\VERSION.txt" (
    for /f "usebackq delims=" %%V in ("%SCRIPT_DIR%\VERSION.txt") do (
        if not defined PATCH_VERSION set "PATCH_VERSION=%%V"
    )
)
if not defined PATCH_VERSION set "PATCH_VERSION=unknown"

echo ===================================================
echo   Building manifest for version %PATCH_VERSION%
echo   Folder: "%SCRIPT_DIR%"
echo ===================================================
echo.

set /a GAME_COUNT=0
set /a TOOL_COUNT=0
set /a FAIL_COUNT=0

> "%TMPFILE%" (
    echo # OIS Community Patch manifest
    echo # Version=%PATCH_VERSION%
    echo # Generated=%DATE% %TIME%
    echo # Format: ^<scope^> ^<sha256^> ^<filename^>
    echo #   game = copied into the game folder
    echo #   tool = package only ^(scripts and docs^)
)

for %%F in ("%SCRIPT_DIR%\*.dll") do call :Emit game "%%~nxF"
for %%F in (%TOOL_FILES%) do if exist "%SCRIPT_DIR%\%%~F" call :Emit tool "%%~F"

if %GAME_COUNT% EQU 0 (
    echo [ERROR] No .dll files found. Run this from inside the patch folder.
    del /F /Q "%TMPFILE%" >nul 2>&1
    echo.
    pause
    exit /b 1
)
if %FAIL_COUNT% GTR 0 (
    echo.
    echo [ERROR] %FAIL_COUNT% file^(s^) could not be hashed. Manifest not written.
    del /F /Q "%TMPFILE%" >nul 2>&1
    echo.
    pause
    exit /b 1
)

move /Y "%TMPFILE%" "%MANIFEST%" >nul
echo.
echo Wrote "%MANIFEST%"
echo   game files: %GAME_COUNT%
echo   tool files: %TOOL_COUNT%
echo.
echo Commit manifest.txt with your changed files.
echo.
pause
exit /b 0


:Emit
call :HashFile "%SCRIPT_DIR%\%~2"
if errorlevel 1 (
    echo [ERROR] Could not hash: %~2
    set /a FAIL_COUNT+=1
    exit /b 0
)
>> "%TMPFILE%" echo %~1 %HASH% %~2
if /I "%~1"=="game" set /a GAME_COUNT+=1
if /I "%~1"=="tool" set /a TOOL_COUNT+=1
echo   %~1  %HASH:~0,16%...  %~2
exit /b 0


rem certutil is on every Windows since 7 and launches in ~30ms, so 30 files
rem hash in about a second. Older Windows prints the digest as space
rem separated byte pairs, hence the space strip.
:HashFile
set "HASH="
for /f "usebackq skip=1 delims=" %%H in (`certutil -hashfile "%~1" SHA256 2^>nul`) do (
    if not defined HASH set "HASH=%%H"
)
if not defined HASH exit /b 1
set "HASH=%HASH: =%"
if not defined HASH exit /b 1
exit /b 0