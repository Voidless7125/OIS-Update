@echo off
setlocal EnableExtensions DisableDelayedExpansion
title OIS Community Patch - Repair

rem =====================================================================
rem  OIS_Health_Check.bat  [options] [game folder]
rem
rem  Everyday use:
rem    (no options)       check the game folder, report drift
rem    -repair            check and put back anything that changed
rem
rem  Setup:
rem    -install-shortcut  copy the package to LocalAppData and create a
rem                       "Repair Objects in Space Patch" shortcut on the
rem                       Desktop and Start Menu. No admin required.
rem    -remove-shortcut   delete those shortcuts
rem
rem  Advanced (not the default, see notes at :InstallTask):
rem    -install-task      register a per-user scheduled task at logon that
rem                       runs minimized and closes itself when done
rem    -remove-task       unregister it
rem
rem  Internal:
rem    -quiet             log only, no console output
rem    -elevated          set when relaunching itself for write access
rem
rem  Reads OIS_Update.manifest.txt from the game folder and compares the
rem  SHA256 of every listed file. Detects Steam "Verify integrity of game
rem  files", which silently restores the vanilla DLLs.
rem
rem  The interactive checker can hand off to Patch_OIS.bat, which offers an
rem  online update check and then repairs the full install from the package.
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SELF=%~f0"

set "TASK_NAME=OIS Community Patch Integrity"
set "USER_ROOT=%LOCALAPPDATA%\OIS-Update"
set "LOG_FILE=%USER_ROOT%\health.log"
set "GAME_MANIFEST_NAME=OIS_Update.manifest.txt"
set "SHORTCUT_NAME=Repair Objects in Space Patch.lnk"
set "TARGET_HINT=%TEMP%\ois_repair_target.txt"
set "TASK_LAUNCHER=%USER_ROOT%\ois_task_launcher.vbs"

set "DO_REPAIR=0"
set "QUIET=0"
set "ELEVATED=0"
set "MODE="
set "TARGET_DIR="

call :ParseArgs %*

if "%QUIET%"=="1" (
    title OIS Patch - checking install
    echo(OIS Community Patch: quick integrity check...
)

if /I "%MODE%"=="install-shortcut" goto :InstallShortcut
if /I "%MODE%"=="remove-shortcut"  goto :RemoveShortcut
if /I "%MODE%"=="install-task"       goto :InstallTask
if /I "%MODE%"=="install-task-daily" goto :InstallTask
if /I "%MODE%"=="remove-task"      goto :RemoveTask

if not defined TARGET_DIR call :FindTarget
if not defined TARGET_DIR (
    call :Say "[ERROR] Could not locate the Objects in Space folder."
    call :Log  "ERROR no game folder found"
    if "%QUIET%"=="0" pause
    exit /b 1
)

set "GAME_MANIFEST=%TARGET_DIR%\%GAME_MANIFEST_NAME%"
if not exist "%GAME_MANIFEST%" (
    call :Say "[ERROR] No installed manifest found in the game folder."
    call :Say "        Run Patch_OIS.bat first."
    call :Log  "ERROR no installed manifest in %TARGET_DIR%"
    if "%QUIET%"=="0" pause
    exit /b 1
)

call :OfferPatchInstall
if errorlevel 2 exit /b 0

call :MaybeElevate

set /a OK_COUNT=0
set /a DRIFT_COUNT=0
set /a FIXED_COUNT=0
set /a UNFIXED_COUNT=0

set "MSG=Checking %TARGET_DIR% ..."
call :Say "%MSG%"
call :Say ""
for /f "usebackq eol=# tokens=1,* delims= " %%A in ("%GAME_MANIFEST%") do call :CheckOne "%%~B" "%%~A"

call :Say ""
call :Say "  matching: %OK_COUNT%   changed: %DRIFT_COUNT%   repaired: %FIXED_COUNT%   unrepaired: %UNFIXED_COUNT%"

if %DRIFT_COUNT% EQU 0 (
    call :Log "OK all %OK_COUNT% files match"
    if "%QUIET%"=="0" (
        echo.
        echo The patch is intact. Nothing to do.
        echo.
        pause
    )
    exit /b 0
)

call :Log "DRIFT %DRIFT_COUNT% changed, repaired %FIXED_COUNT%, unrepaired %UNFIXED_COUNT%"

if "%DO_REPAIR%"=="0" (
    call :Say ""
    call :Say "The patch is no longer intact. This almost always means Steam"
    call :Say "verified the game files and restored the vanilla DLLs."
    if "%QUIET%"=="0" (
        echo.
        choice /C YN /M "Re-apply the patch now?"
        if not errorlevel 2 (
            set "DO_REPAIR=1"
            goto :RepairPass
        )
        echo.
        pause
    )
    exit /b 2
)
goto :RepairDone

:RepairPass
call :MaybeElevate
set /a FIXED_COUNT=0
set /a UNFIXED_COUNT=0
echo.
for /f "usebackq eol=# tokens=1,* delims= " %%A in ("%GAME_MANIFEST%") do call :RepairIfNeeded "%%~B" "%%~A"
call :Log "REPAIR repaired %FIXED_COUNT%, unrepaired %UNFIXED_COUNT%"

:RepairDone
if %UNFIXED_COUNT% GTR 0 (
    call :Say ""
    call :Say "[WARNING] %UNFIXED_COUNT% file^(s^) could not be repaired."
    call :Say "          Run Patch_OIS.bat from the full patch package."
    if "%QUIET%"=="0" (
        echo.
        pause
    )
    exit /b 2
)
if "%QUIET%"=="0" (
    echo.
    echo Patch re-applied. %FIXED_COUNT% file^(s^) restored.
    echo.
    pause
)
exit /b 0


rem --------------------------------------------------------- update/install
:OfferPatchInstall
if "%QUIET%"=="1" exit /b 0
if not exist "%SCRIPT_DIR%\Patch_OIS.bat" exit /b 0
echo.
choice /C YN /M "Run the full patch installer now? It will offer an online update check and repair the install"
if errorlevel 2 exit /b 0
echo.
call "%SCRIPT_DIR%\Patch_OIS.bat" -health-check "%TARGET_DIR%"
if errorlevel 1 (
    echo.
    echo [WARNING] The update or repair did not complete.
    echo Continuing with the local health check.
    echo.
    exit /b 0
)
echo.
echo The full patch installer completed. Health check finished.
echo.
pause
exit /b 2


rem ---------------------------------------------------------------------
:ParseArgs
if "%~1"=="" exit /b 0
if /I "%~1"=="-repair"           ( set "DO_REPAIR=1"            & shift & goto :ParseArgs )
if /I "%~1"=="-quiet"            ( set "QUIET=1"                & shift & goto :ParseArgs )
if /I "%~1"=="-elevated"         ( set "ELEVATED=1"             & shift & goto :ParseArgs )
if /I "%~1"=="-install-shortcut" ( set "MODE=install-shortcut"  & shift & goto :ParseArgs )
if /I "%~1"=="-remove-shortcut"  ( set "MODE=remove-shortcut"   & shift & goto :ParseArgs )
if /I "%~1"=="-install-task"     ( set "MODE=install-task"      & shift & goto :ParseArgs )
if /I "%~1"=="-install-task-daily" ( set "MODE=install-task-daily"  & shift & goto :ParseArgs )
if /I "%~1"=="-remove-task"      ( set "MODE=remove-task"       & shift & goto :ParseArgs )
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
    if "%DO_REPAIR%"=="1" call :Repair "%~1"
    exit /b 0
)
call :HashFile "%TARGET_DIR%\%~1"
if errorlevel 1 (
    set /a DRIFT_COUNT+=1
    set /a UNFIXED_COUNT+=1
    call :Say "  UNREADABLE  %~1"
    exit /b 0
)
if /I "%HASH%"=="%~2" (
    set /a OK_COUNT+=1
    exit /b 0
)
set /a DRIFT_COUNT+=1
call :Say "  CHANGED  %~1"
if "%DO_REPAIR%"=="1" call :Repair "%~1"
exit /b 0


:RepairIfNeeded
if "%~1"=="" exit /b 0
if not exist "%TARGET_DIR%\%~1" (
    call :Repair "%~1"
    exit /b 0
)
call :HashFile "%TARGET_DIR%\%~1"
if errorlevel 1 (
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
if /I "%HASH%"=="%~2" exit /b 0
call :Repair "%~1"
exit /b 0


:Repair
if not exist "%SCRIPT_DIR%\%~1" (
    call :Say "           no local copy of %~1 to repair from"
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
copy /Y "%SCRIPT_DIR%\%~1" "%TARGET_DIR%\%~1" >nul 2>&1
if errorlevel 1 (
    call :Say "           repair failed for %~1 ^(permissions?^)"
    set /a UNFIXED_COUNT+=1
    exit /b 0
)
call :Say "           repaired %~1"
set /a FIXED_COUNT+=1
exit /b 0


rem Steam's default install lives under Program Files, so a repair usually
rem needs write access the shortcut does not have. Rather than making the
rem shortcut permanently elevated (a UAC prompt even for a read-only check
rem on a second drive), the script only asks when it actually cannot write.
:MaybeElevate
if "%DO_REPAIR%"=="0" exit /b 0
if "%QUIET%"=="1" exit /b 0
if "%ELEVATED%"=="1" exit /b 0
call :TestWritable "%TARGET_DIR%"
if not errorlevel 1 exit /b 0
echo.
echo The game folder is not writable by your account.
echo Windows will ask for Administrator permission to repair it.
echo.
call :WriteTargetHint
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Start-Process -FilePath '%SELF%' -ArgumentList '-repair','-elevated' -Verb RunAs" >nul 2>&1
exit


:FindTarget
if defined OIS_TARGET_DIR (
    if exist "%OIS_TARGET_DIR%\ois.exe" (
        set "TARGET_DIR=%OIS_TARGET_DIR%"
        exit /b 0
    )
)
if exist "%TARGET_HINT%" (
    for /f "usebackq delims=" %%T in ("%TARGET_HINT%") do (
        if not defined TARGET_DIR if exist "%%~T\ois.exe" set "TARGET_DIR=%%~T"
    )
    del /F /Q "%TARGET_HINT%" >nul 2>&1
    if defined TARGET_DIR exit /b 0
)
for %%I in ("%ProgramFiles(x86)%\Steam" "%ProgramFiles%\Steam" "%USERPROFILE%\Steam" "%SystemDrive%\Steam") do (
    if exist "%%~I\steamapps\common\Objects in Space\ois.exe" (
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
exit /b 0

:ScanSteamRoot
if exist "%~1\steamapps\common\Objects in Space\ois.exe" (
    set "TARGET_DIR=%~1\steamapps\common\Objects in Space"
    exit /b 0
)
if not exist "%~1\steamapps\libraryfolders.vdf" exit /b 1
for /f "usebackq tokens=2 delims=	 " %%P in (`findstr /I /C:"\"path\"" "%~1\steamapps\libraryfolders.vdf"`) do (
    call :TryLibrary %%P
    if not errorlevel 1 exit /b 0
)
exit /b 1

:TryLibrary
if not exist "%~1\steamapps\common\Objects in Space\ois.exe" exit /b 1
set "TARGET_DIR=%~1\steamapps\common\Objects in Space"
exit /b 0


rem ------------------------------------------------------ shortcut setup
rem This is the recommended setup. It needs no administrator rights at
rem install time, leaves nothing running in the background, and is
rem indistinguishable from any other application shortcut as far as
rem antivirus is concerned. The package is copied into LocalAppData so the
rem shortcut keeps working after the user deletes their Downloads folder,
rem which they will.
:InstallShortcut
if not defined TARGET_DIR call :FindTarget

echo This creates a shortcut and keeps a copy of the patch package for it.
echo Retained package location:
echo   "%USER_ROOT%"
echo The shortcut uses this folder to repair the install and offer future
echo patch updates after Steam replaces the patched files.
echo This folder can be deleted manually later, but doing so removes the
echo local repair and update copy.
echo.
echo Copying the patch package to:
echo   "%USER_ROOT%"
if not exist "%USER_ROOT%" md "%USER_ROOT%" >nul 2>&1
if not exist "%USER_ROOT%" (
    echo [ERROR] Could not create that folder.
    echo.
    pause
    exit /b 1
)
if not exist "%USER_ROOT%\Original" md "%USER_ROOT%\Original" >nul 2>&1
copy /Y "%SCRIPT_DIR%\*.dll" "%USER_ROOT%\" >nul 2>&1
if exist "%SCRIPT_DIR%\Original\*.dll" copy /Y "%SCRIPT_DIR%\Original\*.dll" "%USER_ROOT%\Original\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\manifest.txt" "%USER_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\VERSION.txt" "%USER_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\Patch_OIS.bat" "%USER_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\OIS_Health_Check.bat" "%USER_ROOT%\" >nul 2>&1

set "SHORTCUT_TARGET=%USER_ROOT%\OIS_Health_Check.bat"
if not exist "%SHORTCUT_TARGET%" set "SHORTCUT_TARGET=%SELF%"

set "ICON=%SystemRoot%\System32\shell32.dll,238"
if defined TARGET_DIR if exist "%TARGET_DIR%\ois.exe" set "ICON=%TARGET_DIR%\ois.exe,0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $w=New-Object -ComObject WScript.Shell; $dests=@(); $d1=Join-Path $env:USERPROFILE 'Desktop'; $d2=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'; foreach($d in @($d1,$d2)){ if(Test-Path -LiteralPath $d){ $dests += $d } }; foreach($d in $dests){ $s=$w.CreateShortcut((Join-Path $d '%SHORTCUT_NAME%')); $s.TargetPath='%SHORTCUT_TARGET%'; $s.Arguments='-repair'; $s.WorkingDirectory='%USER_ROOT%'; $s.IconLocation='%ICON%'; $s.Description='Re-apply the Objects in Space Community Patch after Steam verifies game files'; $s.Save() }" >nul 2>&1

if exist "%USERPROFILE%\Desktop\%SHORTCUT_NAME%" goto :ShortcutOk
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\%SHORTCUT_NAME%" goto :ShortcutOk
echo [WARNING] The shortcut could not be created.
echo You can still repair by running OIS_Health_Check.bat -repair
echo.
pause
exit /b 1

:ShortcutOk
echo.
echo Created "Repair Objects in Space Patch" on your Desktop and Start Menu.
echo The repair and update package is stored at:
echo   "%USER_ROOT%"
echo.
echo If Steam ever verifies your game files and the patch stops applying,
echo click that shortcut. It re-checks every file and puts back anything
echo Steam reverted. It stays offline unless you choose the full installer
echo and its online update check.
echo.
echo Remove it later with:  OIS_Health_Check.bat -remove-shortcut
echo.
if "%QUIET%"=="0" pause
exit /b 0


:RemoveShortcut
del /F /Q "%USERPROFILE%\Desktop\%SHORTCUT_NAME%" >nul 2>&1
del /F /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\%SHORTCUT_NAME%" >nul 2>&1
echo Shortcuts removed.
echo The package copy under "%USER_ROOT%" was left in place.
echo Delete that folder by hand if you no longer want it.
echo.
pause
exit /b 0

rem --------------------------------------------------------- target hint
rem This is a temporary file that stores the game folder path when the script
rem relaunches itself for elevated permission. It is deleted after the elevated run completes.
:WriteTargetHint
> "%TARGET_HINT%" echo %TARGET_DIR%
exit /b 0

rem --------------------------------------------------------- write test
rem Just a helper function for InstallTask for testing whether the current account can write to the game folder. 
rem If it cannot, the scheduled task will not be able to repair anything, and it will silently log "unrepaired" 
rem without prompting for permission. The Desktop/Start Menu shortcut does not have this problem, since it 
rem can prompt for permission when needed. The automatic task is not recommended for a folder that cannot be 
rem written to by the current account.
:TestWritable
break > "%~1\ois_write_test.tmp" 2>nul
if exist "%~1\ois_write_test.tmp" (
    del /F /Q "%~1\ois_write_test.tmp" >nul 2>&1
    exit /b 0
)
exit /b 1

rem ------------------------------------------------- advanced: scheduled
rem Registers a task under the CURRENT user only - no admin rights, no
rem SYSTEM privilege, nothing this account couldn't already do by hand.
rem It runs minimized at logon, checks the manifest, repairs any drift,
rem and closes itself; nothing lingers in the background afterward.
rem Still opt-in, not the default: it solves a problem (Steam's "Verify
rem integrity" silently reverting the patch) that fires roughly once per
rem user per year, and the Desktop/Start Menu shortcut from
rem -install-shortcut covers the same need on demand without anything
rem running unattended. Patch_OIS.bat's installer offers a choice between
rem the manual shortcut and this automatic task; -install-task also
rem remains directly available for anyone who skipped that prompt.
:InstallTask
if not defined TARGET_DIR call :FindTarget
if not defined TARGET_DIR (
    echo [ERROR] Could not locate the game folder. Pass it as an argument:
    echo   OIS_Health_Check.bat -install-task "D:\SteamLibrary\steamapps\common\Objects in Space"
    echo.
    pause
    exit /b 1
)

call :TestWritable "%TARGET_DIR%"
if not errorlevel 1 goto :TaskFolderWritable

echo.
echo [WARNING] This account cannot write to the game folder:
echo   "%TARGET_DIR%"
echo.
echo The automatic task runs -quiet, which never prompts for the
echo Administrator permission a repair might need here. If Steam
echo reverts a file, the task will detect it and log "unrepaired"
echo silently - it will NOT fix it and will NOT tell you.
echo.
echo The Desktop/Start Menu shortcut ^(-install-shortcut^) doesn't have
echo this problem, since it can prompt for permission when needed.
echo The automatic task is NOT recommended for this folder.
echo.
choice /C YN /M "Install the automatic task anyway?"
if not errorlevel 2 goto :TaskFolderWritable
echo.
echo Skipped. Use OIS_Health_Check.bat -install-shortcut instead.
echo.
pause
exit /b 0

:TaskFolderWritable
echo Copying the patch package to "%USER_ROOT%" ...
if not exist "%USER_ROOT%" md "%USER_ROOT%" >nul 2>&1
if not exist "%USER_ROOT%\Original" md "%USER_ROOT%\Original" >nul 2>&1
copy /Y "%SCRIPT_DIR%\*.dll" "%USER_ROOT%\" >nul 2>&1
if exist "%SCRIPT_DIR%\Original\*.dll" copy /Y "%SCRIPT_DIR%\Original\*.dll" "%USER_ROOT%\Original\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\manifest.txt" "%USER_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\VERSION.txt" "%USER_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\Patch_OIS.bat" "%USER_ROOT%\" >nul 2>&1
copy /Y "%SCRIPT_DIR%\OIS_Health_Check.bat" "%USER_ROOT%\" >nul 2>&1

> "%TASK_LAUNCHER%" echo Set objShell = CreateObject("WScript.Shell")
>>"%TASK_LAUNCHER%" echo objShell.Run Chr(34) ^& WScript.Arguments(0) ^& Chr(34) ^& " -repair -quiet " ^& Chr(34) ^& WScript.Arguments(1) ^& Chr(34), 7, False
if not exist "%TASK_LAUNCHER%" (
    echo [ERROR] Could not write the task launcher script.
    echo.
    pause
    exit /b 1
)

set "TASK_CMD=%USER_ROOT%\OIS_Health_Check.bat"
set "TASK_ERR=%TEMP%\ois_schtasks_err.txt"
schtasks /Create /TN "%TASK_NAME%" /TR "wscript.exe //B \"%TASK_LAUNCHER%\" \"%TASK_CMD%\" \"%TARGET_DIR%\"" /SC ONLOGON /F >nul 2>"%TASK_ERR%"
if not errorlevel 1 goto :TaskCreated

findstr /I /C:"Access is denied" "%TASK_ERR%" >nul
if errorlevel 1 goto :TaskCreateFailed
if "%ELEVATED%"=="1" goto :TaskCreateFailed

del /F /Q "%TASK_ERR%" >nul 2>&1
echo.
echo Windows requires one Administrator prompt to register a
echo scheduled task, even though the task itself will only ever
echo run as your own account afterward. This is needed once, at
echo setup - not every time the task runs.
echo.
call :WriteTargetHint
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Start-Process -FilePath '%SELF%' -ArgumentList '-install-task','-elevated' -Verb RunAs -Wait" >nul 2>&1
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if errorlevel 1 goto :TaskCreateStillFailed
goto :TaskCreated

:TaskCreateStillFailed
echo [ERROR] The task still was not created. The Administrator
echo prompt may have been canceled or blocked.
echo.
pause
exit /b 1

:TaskCreateFailed
echo [ERROR] Could not create the scheduled task. Details:
if exist "%TASK_ERR%" type "%TASK_ERR%"
del /F /Q "%TASK_ERR%" >nul 2>&1
echo.
pause
exit /b 1

:TaskCreated
del /F /Q "%TASK_ERR%" >nul 2>&1
echo.
echo Scheduled task created: "%TASK_NAME%"
echo   runs   : at every logon, as you, minimized, closes itself
echo   package: "%USER_ROOT%"
echo   log    : "%LOG_FILE%"
echo.
echo Also run this check once a day at noon, in addition to at logon?
choice /C YN /M "Add a daily check"
if errorlevel 2 goto :TaskAllDone

set "TASK_ERR2=%TEMP%\ois_schtasks_daily_err.txt"
schtasks /Create /TN "%TASK_NAME% Daily" /TR "wscript.exe //B \"%TASK_LAUNCHER%\" \"%TASK_CMD%\" \"%TARGET_DIR%\"" /SC DAILY /ST 12:00 /F >nul 2>"%TASK_ERR2%"
if not errorlevel 1 goto :DailyTaskCreated

findstr /I /C:"Access is denied" "%TASK_ERR2%" >nul
if errorlevel 1 goto :DailyTaskFailed
if "%ELEVATED%"=="1" goto :DailyTaskFailed

del /F /Q "%TASK_ERR2%" >nul 2>&1
echo.
echo One more Administrator prompt is needed for the daily task.
echo.
call :WriteTargetHint
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Start-Process -FilePath '%SELF%' -ArgumentList '-install-task-daily','-elevated' -Verb RunAs -Wait" >nul 2>&1
schtasks /Query /TN "%TASK_NAME% Daily" >nul 2>&1
if errorlevel 1 goto :DailyTaskFailedSilent
goto :DailyTaskCreated

:DailyTaskFailedSilent
echo [WARNING] The daily task was not created. The Administrator prompt
echo may have been canceled or blocked. The logon task is still active.
echo.
goto :TaskAllDone

:DailyTaskFailed
echo [WARNING] Could not create the daily task. Details:
if exist "%TASK_ERR2%" type "%TASK_ERR2%"
del /F /Q "%TASK_ERR2%" >nul 2>&1
echo The logon task is still active regardless.
echo.
goto :TaskAllDone

:DailyTaskCreated
del /F /Q "%TASK_ERR2%" >nul 2>&1
echo.
echo Daily check added: runs at noon in addition to at logon.
echo.

:TaskAllDone
echo To remove either task:  OIS_Health_Check.bat -remove-task
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
echo(%~1
exit /b 0

:Log
if not exist "%USER_ROOT%" md "%USER_ROOT%" >nul 2>&1
>> "%LOG_FILE%" echo %DATE% %TIME%  %~1
exit /b 0