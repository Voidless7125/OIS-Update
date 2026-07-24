@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Objects in Space - Community Patch

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "TARGET_DIR=%~1"
if not defined TARGET_DIR set "TARGET_DIR=%OIS_TARGET_DIR%"
if not defined TARGET_DIR set "TARGET_DIR=C:\Program Files (x86)\Steam\steamapps\common\Objects in Space"

set "STEAM_ROOT="
for %%I in ("%ProgramFiles(x86)%\Steam" "%ProgramFiles%\Steam" "%USERPROFILE%\Steam") do (
    if exist "%%~I\steam.exe" set "STEAM_ROOT=%%~I"
)
if not defined STEAM_ROOT (
    for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul ^| findstr /R /C:"InstallPath"') do (
        if exist "%%B\steam.exe" set "STEAM_ROOT=%%B"
    )
)
if defined STEAM_ROOT if not defined TARGET_DIR set "TARGET_DIR=%STEAM_ROOT%\steamapps\common\Objects in Space"

echo ===================================================
echo   Objects in Space: Community Patch Setup
echo ===================================================
echo.
echo Hello! This script will update your game to run safely and smoothly.
echo.

:: 0. Check if they extracted the ZIP
if not exist "%SCRIPT_DIR%\fmod.dll" (
    echo [ERROR] The patch files are missing!
    echo.
    echo If you are running this from inside a downloaded ZIP file, it won't work.
    echo Please EXTRACT the entire folder to your PC ^(like your Desktop^),
    echo and then run this script again from the new unzipped folder.
    echo.
    pause
    exit /b 1
)

:: 1. Verify the game is installed in the expected location
if exist "%TARGET_DIR%\ois.exe" goto :GameFound
if exist "%TARGET_DIR%\ois_server.exe" goto :GameFound

echo [ERROR] Could not automatically find your Objects in Space installation.
echo Checked location: "%TARGET_DIR%"
echo.
echo If you have the game installed on a different drive ^(like D: or E:^),
echo you can run this script with the game folder as an argument.
echo Example: Patch_OIS.bat "D:\Games\Objects in Space"
echo.
pause
exit /b 1

:GameFound
:: 2. Copy all DLLs (Runs as standard user)
echo [1/3] Copying updated game files...
for %%F in ("%SCRIPT_DIR%\*.dll") do (
    copy /Y "%%~fF" "%TARGET_DIR%\" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy "%%~nxF".
        pause
        exit /b 1
    )
)
echo       Files copied successfully!
echo.

:: 3. Cleanup redundancy
echo [2/3] Cleaning up extra files...
for %%F in ("libcrypto-3.dll" "libssl-3.dll" "libiconv-2.dll") do (
    if exist "%TARGET_DIR%\%%~F" del /Q "%TARGET_DIR%\%%~F"
)
echo       Cleanup complete.
echo.

:: 4. Optional Firewall Security (Requires explicit user opt-in)
echo [3/3] Security Configuration
echo To keep your computer completely safe while playing this older game,
echo it is highly recommended to block it from accepting outside internet connections.
echo.
choice /C YN /M "Would you like me to secure the game using Windows Firewall? (Recommended) [Y/N]?"
if errorlevel 2 goto :SkipFirewall
if errorlevel 1 goto :ApplyFirewall

:ApplyFirewall
echo.
echo [Windows will now ask for Administrator permission to update your Firewall]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c netsh advfirewall firewall delete rule name=\"OIS_Client_Block_Inbound\" >nul 2^>^&1 & netsh advfirewall firewall delete rule name=\"OIS_Server_Block_Inbound\" >nul 2^>^&1 & netsh advfirewall firewall add rule name=\"OIS_Client_Block_Inbound\" description=\"Community Patch: Blocks inbound connections to secure legacy libwebsockets.\" dir=in action=block program=\"%TARGET_DIR%\ois.exe\" enable=yes profile=any edge=no >nul & netsh advfirewall firewall add rule name=\"OIS_Server_Block_Inbound\" description=\"Community Patch: Blocks inbound connections to secure legacy libwebsockets.\" dir=in action=block program=\"%TARGET_DIR%\ois_server.exe\" enable=yes profile=any edge=no >nul' -Verb RunAs -Wait"
echo.
echo Firewall rules successfully applied! You are good to go.
goto :Finish

:SkipFirewall
echo.
echo Skipping Firewall rules. ^(Please be careful playing on public servers!^)
goto :Finish

:Finish
echo.
echo ===================================================
echo   SUCCESS! Objects in Space is ready to play.
echo.
echo   If you experience any issues or crashes, please
echo   report them on the Steam community discussions!
echo.
echo   You can now close this window.
echo ===================================================
echo.
pause