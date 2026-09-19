@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Vadder - start game
set "SteamAppId=892970"

set "VADDER_LOCAL=%LOCALAPPDATA%\Vadder"
set "MODS_BASE=%APPDATA%\r2modmanPlus-local\Valheim\profiles\valheim_vadder_sync"

echo ===============================================
echo    Vadder - start Valheim
echo ===============================================
echo.

if not exist "%MODS_BASE%\winhttp.dll" (
    echo [Vadder] ERROR: profile is missing winhttp.dll - run the mods update first.
    goto :fail_pause
)
if not exist "%MODS_BASE%\doorstop_config.ini" (
    echo [Vadder] ERROR: profile is missing doorstop_config.ini - run the mods update first.
    goto :fail_pause
)

rem --- locate the game -------------------------------------------------------
set "GAME_DIR=%VADDER_GAME_DIR%"
if defined GAME_DIR (
    if exist "%GAME_DIR%\valheim.exe" (
        echo [Vadder] Using game dir from VADDER_GAME_DIR.
        goto :game_ok
    )
    echo [Vadder] ERROR: VADDER_GAME_DIR does not contain valheim.exe: "%GAME_DIR%"
    goto :fail_pause
)

call :find_steam
if defined GAME_DIR goto :game_ok

call :read_stored_path
if defined GAME_DIR goto :game_ok

echo [Vadder] Could not find Valheim automatically.
set "GAME_DIR="
set /p "GAME_DIR=Paste the full folder path where valheim.exe is located: "
if not defined GAME_DIR (
    echo [Vadder] No path given, aborting.
    goto :fail_pause
)
if not exist "%GAME_DIR%\valheim.exe" (
    echo [Vadder] ERROR: that folder has no valheim.exe in it.
    goto :fail_pause
)
> "%VADDER_LOCAL%\game-path.config" echo %GAME_DIR%
echo [Vadder] Path saved to %VADDER_LOCAL%\game-path.config

:game_ok
echo [Vadder] Game directory: %GAME_DIR%

rem debug/test hook: resolve and report, then stop
if "%VADDER_DRY_RUN%"=="1" (
    echo [Vadder] DRY RUN - not creating links or launching.
    pause
    exit /b 0
)

rem --- writability check + hardlinks -----------------------------------------
set "PROBE=%GAME_DIR%\.vadder-write.tmp"
echo x> "%PROBE%" 2>nul
if not exist "%PROBE%" (
    echo [Vadder] ERROR: cannot write to the game directory. Run once as admin or move Valheim to a writable drive.
    goto :fail_pause
)
del "%PROBE%" 2>nul

if not exist "%GAME_DIR%\winhttp.dll" (
    echo [Vadder] Linking winhttp.dll...
    mklink /H "%GAME_DIR%\winhttp.dll" "%MODS_BASE%\winhttp.dll"
    if errorlevel 1 (
        echo [Vadder] ERROR: could not hardlink winhttp.dll. Is the game folder on the same drive as %MODS_BASE%?
        goto :fail_pause
    )
)
if not exist "%GAME_DIR%\doorstop_config.ini" (
    echo [Vadder] Linking doorstop_config.ini...
    mklink /H "%GAME_DIR%\doorstop_config.ini" "%MODS_BASE%\doorstop_config.ini"
    if errorlevel 1 (
        echo [Vadder] ERROR: could not hardlink doorstop_config.ini.
        goto :fail_pause
    )
)

rem --- launch -------------------------------------------------------------------
echo [Vadder] Starting Valheim... ^(close the window or PRESS CTRL-C to quit^)
cd /d "%GAME_DIR%"
valheim.exe --doorstop-enable true --doorstop-target-assembly "%MODS_BASE%\BepInEx\core\BepInEx.Preloader.dll"
set "GAME_EXIT=%errorlevel%"
echo [Vadder] Valheim exited with code %GAME_EXIT%.
pause
exit /b %GAME_EXIT%

:find_steam
set "STEAM_PATH="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath; if($p){ $p }"`) do set "STEAM_PATH=%%p"
if not defined STEAM_PATH (
    echo [Vadder] Steam registry key not found.
    exit /b 0
)

rem primary library
set "GAME_DIR=%STEAM_PATH%\steamapps\common\Valheim"
if exist "%GAME_DIR%\valheim.exe" exit /b 0
set "GAME_DIR="

rem additional libraries from libraryfolders.vdf
set "VDF=%STEAM_PATH%\steamapps\libraryfolders.vdf"
if not exist "%VDF%" exit /b 0
for /f "usebackq tokens=3 delims=" %%c in (`findstr /C:"path" "%VDF%"`) do (
    set "CAND=%%c"
    set "CAND=!CAND:\\=\!"
    if not defined GAME_DIR if exist "!CAND!\steamapps\common\Valheim\valheim.exe" set "GAME_DIR=!CAND!\steamapps\common\Valheim"
)
exit /b 0

:read_stored_path
if not exist "%VADDER_LOCAL%\game-path.config" exit /b 0
set /p "GAME_DIR=" < "%VADDER_LOCAL%\game-path.config"
if not defined GAME_DIR exit /b 0
if exist "%GAME_DIR%\valheim.exe" exit /b 0
echo [Vadder] Stored game path is stale, ignoring: %GAME_DIR%
set "GAME_DIR="
exit /b 0

:fail_pause
echo.
pause
exit /b 1