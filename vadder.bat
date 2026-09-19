@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Vadder

if "%VADDER_SERVER%"=="" set "VADDER_SERVER=http://ds.hiijac.com:2460"
set "VADDER_LOCAL=%LOCALAPPDATA%\Vadder"
set "SCRIPTS_DIR=%VADDER_LOCAL%\client-scripts"
set "SCRIPTS_ZIP=%VADDER_LOCAL%\scripts.zip"
set "HASH_REMOTE=%VADDER_LOCAL%\scripts.hash.remote"
set "HASH_LIVE=%VADDER_LOCAL%\scripts.hash"
set "CURL_ERR=%VADDER_LOCAL%\curl.err"

echo ===============================================
echo    Vadder - Valheim mod sync client
echo    Server: %VADDER_SERVER%
echo ===============================================
echo.

if not exist "%VADDER_LOCAL%" mkdir "%VADDER_LOCAL%"

where curl.exe >nul 2>nul
if errorlevel 1 goto :fail_no_curl

call :update_scripts
if errorlevel 1 exit /b 1

if not exist "%SCRIPTS_DIR%\entry.bat" (
    echo [Vadder] ERROR: entry.bat is missing after the update.
    goto :fail_pause
)

echo [Vadder] Running client scripts...
call "%SCRIPTS_DIR%\entry.bat"
set "RESULT=%errorlevel%"

del "%SCRIPTS_ZIP%" "%HASH_REMOTE%" 2>nul

echo.
if "%RESULT%"=="0" (
    echo [Vadder] All done.
) else (
    echo [Vadder] Finished with code %RESULT%.
)
exit /b %RESULT%

:update_scripts
echo [1/2] Checking client scripts on %VADDER_SERVER% ...
curl.exe -f -sS -m 20 "%VADDER_SERVER%/api/scripts/hash" -o "%HASH_REMOTE%" 2>"%CURL_ERR%"
if errorlevel 1 goto :fail_net

set "CHANGED="
if not exist "%HASH_LIVE%" (
    set "CHANGED=1"
) else (
    fc /b "%HASH_REMOTE%" "%HASH_LIVE%" >nul 2>nul
    if errorlevel 1 set "CHANGED=1"
)

if not defined CHANGED (
    echo [Vadder] Client scripts are up to date.
    exit /b 0
)

echo [Vadder] Scripts changed, downloading...
curl.exe -f -sS -m 180 "%VADDER_SERVER%/api/scripts/zip" -o "%SCRIPTS_ZIP%" 2>>"%CURL_ERR%"
if errorlevel 1 goto :fail_net

set /p "ANNOUNCED=" < "%HASH_REMOTE%"
if not defined ANNOUNCED (
    echo [Vadder] ERROR: server returned an empty hash.
    exit /b 1
)
set "VADDER_VERIFY_FILE=%SCRIPTS_ZIP%"
set "VADDER_VERIFY_EXPECT=%ANNOUNCED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -LiteralPath $env:VADDER_VERIFY_FILE -Algorithm SHA256).Hash.ToLowerInvariant(); if($h -ne $env:VADDER_VERIFY_EXPECT){Write-Output ('mismatch: '+$h); exit 1}"
if errorlevel 1 (
    echo [Vadder] ERROR: downloaded scripts.zip does not match the announced hash.
    del "%SCRIPTS_ZIP%" 2>nul
    exit /b 1
)

if exist "%SCRIPTS_DIR%" rmdir /s /q "%SCRIPTS_DIR%"
mkdir "%SCRIPTS_DIR%"
tar.exe -xf "%SCRIPTS_ZIP%" -C "%SCRIPTS_DIR%"
if errorlevel 1 (
    echo [Vadder] ERROR: failed to unpack client scripts.
    rmdir /s /q "%SCRIPTS_DIR%" 2>nul
    del "%SCRIPTS_ZIP%" 2>nul
    exit /b 1
)
move /y "%HASH_REMOTE%" "%HASH_LIVE%" >nul
echo [Vadder] Client scripts updated.
exit /b 0

:fail_no_curl
echo [Vadder] ERROR: curl.exe not found. It ships with Windows 11.
goto :fail_pause

:fail_net
echo [Vadder] ERROR: could not reach %VADDER_SERVER%.
if exist "%CURL_ERR%" type "%CURL_ERR%"
echo [Vadder]   Is the server up and is port 2460 reachable?
goto :fail_pause

:fail_pause
echo.
pause
exit /b 1