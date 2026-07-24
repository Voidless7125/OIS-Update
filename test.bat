@echo off
title Objects in Space - Community Patch

set "TARGET_DIR=C:\Program Files (x86)\Steam\steamapps\common\Objects in Space"

echo ===================================================
echo   Objects in Space: Community Patch Setup
echo ===================================================
echo.
echo Hello! This script will update your game to run safely and smoothly.
echo.

:: 0. Check if they extracted the ZIP
if not exist "%~dp0fmod.dll" (
    echo [ERROR] The patch files are missing!
    echo.
    echo If you are running this from inside a downloaded ZIP file, it won't work.
    echo Please EXTRACT the entire folder to your PC ^(like your Desktop^), 
    echo and then run this script again from the new unzipped folder.
    echo.
    pause
    exit /b
)

:: 1. Verify the game is installed in the default location
if exist "%TARGET_DIR%\ois.exe" goto :GameFound

echo [ERROR] Could not automatically find your Objects in Space installation.
echo Checked location: "%TARGET_DIR%"
echo.
echo If you have the game installed on a different drive ^(like D: or E:^), 
echo you will need to copy the DLL files manually into your game folder.
echo.
pause
exit /b

:GameFound
:: 2. Copy all DLLs (Runs as standard user)
echo [1/3] Copying updated game files...
xcopy "%~dp0*.dll" "%TARGET_DIR%\" /Y /V /Q >nul
echo       Files copied successfully!
echo.

:: 3. Cleanup redundancy
echo [2/3] Cleaning up extra files...
if exist "%TARGET_DIR%\libcrypto-3.dll" del /Q "%TARGET_DIR%\libcrypto-3.dll"
if exist "%TARGET_DIR%\libssl-3.dll" del /Q "%TARGET_DIR%\libssl-3.dll"
if exist "%TARGET_DIR%\libiconv-2.dll" del /Q "%TARGET_DIR%\libiconv-2.dll"
echo       Cleanup complete.
echo.

:: 4. Optional Firewall Security (Requires explicit user opt-in)
echo [3/3] Security Configuration
echo To keep your computer completely safe while playing this older game, 
echo it is highly recommended to block it from accepting outside internet connections.
echo.
choice /C YN /M "Would you like me to secure the game using Windows Firewall? (Recommended)"
if errorlevel 2 goto SkipFirewall
if errorlevel 1 goto ApplyFirewall

:ApplyFirewall
echo.
echo [Windows will now ask for Administrator permission to update your Firewall]

:: Execute all firewall commands strictly in-memory without dropping a temp file
powershell -Command "Start-Process cmd -ArgumentList '/c netsh advfirewall firewall delete rule name=\"OIS_Client_Block_Inbound\" ^>nul 2^>^&1 & netsh advfirewall firewall delete rule name=\"OIS_Server_Block_Inbound\" ^>nul 2^>^&1 & netsh advfirewall firewall add rule name=\"OIS_Client_Block_Inbound\" description=\"Community Patch: Blocks inbound connections to secure legacy libwebsockets.\" dir=in action=block program=\"%TARGET_DIR%\ois.exe\" enable=yes profile=any edge=no ^>nul & netsh advfirewall firewall add rule name=\"OIS_Server_Block_Inbound\" description=\"Community Patch: Blocks inbound connections to secure legacy libwebsockets.\" dir=in action=block program=\"%TARGET_DIR%\server.exe\" enable=yes profile=any edge=no ^>nul' -Verb RunAs -Wait"

echo.
echo Firewall rules successfully applied! You are good to go.
goto Finish

:SkipFirewall
echo.
echo Skipping Firewall rules. ^(Please be careful playing on public servers!^)
goto Finish

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