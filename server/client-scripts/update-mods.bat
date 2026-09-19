@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Vadder - mods

if "%VADDER_SERVER%"=="" set "VADDER_SERVER=http://ds.hiijac.com:2460"
set "VADDER_LOCAL=%LOCALAPPDATA%\Vadder"
set "MODS_ROOT=%APPDATA%\r2modmanPlus-local\Valheim\profiles"
set "MODS_SYNC=%MODS_ROOT%\valheim_vadder_sync"
set "MODS_TEST=%MODS_ROOT%\valheim_vadder_test"
set "HASH_REMOTE=%VADDER_LOCAL%\mods.hash.remote"
set "HASH_LIVE=%VADDER_LOCAL%\mods.hash"
set "MODS_ZIP=%VADDER_LOCAL%\mods.zip"
set "CFG_BACKUP=%VADDER_LOCAL%\cfg-backup.tmp"
set "CURL_ERR=%VADDER_LOCAL%\curl.err"

echo ===============================================
echo    Vadder - mods update
echo    Server: %VADDER_SERVER%
echo ===============================================
echo.

if not exist "%VADDER_LOCAL%" mkdir "%VADDER_LOCAL%"

where curl.exe >nul 2>nul
if errorlevel 1 goto :fail_no_curl

set "TARGET=%MODS_SYNC%"
if exist "%MODS_SYNC%\VADDER_WRITABLE" goto :mode_defined
if not exist "%MODS_SYNC%" goto :mode_defined

rem sync dir exists but is not marked: this smells like the server machine
curl.exe -f -sS -m 10 "%VADDER_SERVER%/api/mods/hash" -o "%HASH_REMOTE%" 2>"%CURL_ERR%"
if errorlevel 1 goto :fail_unmanaged
echo [Vadder] Server profile detected - writing to valheim_vadder_test instead.
set "TARGET=%MODS_TEST%"

:mode_defined
echo [Vadder] Using profile: %TARGET%

rem fetch current hash
curl.exe -f -sS -m 20 "%VADDER_SERVER%/api/mods/hash" -o "%HASH_REMOTE%" 2>"%CURL_ERR%"
if errorlevel 1 goto :fail_net

set "CHANGED="
if not exist "%HASH_LIVE%" (
    set "CHANGED=1"
) else (
    fc /b "%HASH_REMOTE%" "%HASH_LIVE%" >nul 2>nul
    if errorlevel 1 set "CHANGED=1"
)

if not defined CHANGED (
    echo [Vadder] Mods are up to date, nothing to do.
    exit /b 0
)

echo [Vadder] Mods changed, downloading...
curl.exe -f -sS -m 600 "%VADDER_SERVER%/api/mods/zip" -o "%MODS_ZIP%" 2>>"%CURL_ERR%"
if errorlevel 1 goto :fail_net

set /p "ANNOUNCED=" < "%HASH_REMOTE%"
if not defined ANNOUNCED (
    echo [Vadder] ERROR: server returned an empty hash.
    goto :fail_pause
)
set "VADDER_VERIFY_FILE=%MODS_ZIP%"
set "VADDER_VERIFY_EXPECT=%ANNOUNCED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -LiteralPath $env:VADDER_VERIFY_FILE -Algorithm SHA256).Hash.ToLowerInvariant(); if($h -ne $env:VADDER_VERIFY_EXPECT){Write-Output ('mismatch: '+$h); exit 1}"
if errorlevel 1 (
    echo [Vadder] ERROR: downloaded mods.zip does not match the announced hash.
    del "%MODS_ZIP%" 2>nul
    goto :fail_pause
)

echo [Vadder] Installing to %TARGET% ...

rem backup the personal config, if any
if exist "%TARGET%\BepInEx\config" (
    echo [Vadder] Backing up BepInEx config...
    if exist "%CFG_BACKUP%" rmdir /s /q "%CFG_BACKUP%"
    mkdir "%CFG_BACKUP%"
    robocopy "%TARGET%\BepInEx\config" "%CFG_BACKUP%" /E /NJH /NJS /NFL /NDL >nul
    if errorlevel 8 (
        echo [Vadder] ERROR: could not back up the config folder.
        goto :fail_pause
    )
)

rem wipe the old profile entirely
rmdir /s /q "%TARGET%" 2>nul
if exist "%TARGET%" (
    attrib -r -h -s "%TARGET%\*.*" /s /d 2>nul
    rmdir /s /q "%TARGET%" 2>nul
)
if exist "%TARGET%" (
    echo [Vadder] ERROR: could not clear the old profile "%TARGET%".
    goto :fail_pause
)
mkdir "%TARGET%"

rem unpack the fresh profile
tar.exe -xf "%MODS_ZIP%" -C "%TARGET%"
if errorlevel 1 (
    echo [Vadder] ERROR: failed to unpack mods.zip.
    goto :fail_pause
)

rem restore the personal config on top of the fresh one
if exist "%CFG_BACKUP%" (
    echo [Vadder] Restoring your local BepInEx config...
    robocopy "%CFG_BACKUP%" "%TARGET%\BepInEx\config" /E /NJH /NJS /NFL /NDL >nul
    if errorlevel 8 (
        echo [Vadder] WARNING: could not restore the config backup.
    )
    rmdir /s /q "%CFG_BACKUP%" 2>nul
)

del "%MODS_ZIP%" 2>nul
move /y "%HASH_REMOTE%" "%HASH_LIVE%" >nul
echo [Vadder] Mods updated.
exit /b 0

:fail_no_curl
echo [Vadder] ERROR: curl.exe not found. It ships with Windows 11.
goto :fail_pause

:fail_net
echo [Vadder] ERROR: could not reach %VADDER_SERVER%.
if exist "%CURL_ERR%" type "%CURL_ERR%"
echo [Vadder]   Is the server up and is port 2460 reachable?
goto :fail_pause

:fail_unmanaged
echo [Vadder] ERROR: %MODS_SYNC% exists but has no VADDER_WRITABLE marker
echo          and the server is unreachable. Vadder only touches profiles it
echo          created itself, so it refuses to modify this one.
goto :fail_pause

:fail_pause
echo.
pause
exit /b 1