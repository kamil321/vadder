@echo off
set "SteamAppId=892970"
set "VALHEIM_DIR=C:\Program Files (x86)\Steam\steamapps\common\Valheim"
set "MODPATH=%APPDATA%\r2modmanPlus-local\Valheim\profiles\valheim"

if not exist "%VALHEIM_DIR%\winhttp.dll" (
    echo Creating hard link for winhttp.dll...
    mklink /H "%VALHEIM_DIR%\winhttp.dll" "%MODPATH%\winhttp.dll"
)

if not exist "%VALHEIM_DIR%\doorstop_config.ini" (
    echo Creating hard link for doorstop_config.ini...
    mklink /H "%VALHEIM_DIR%\doorstop_config.ini" "%MODPATH%\doorstop_config.ini"
)

echo Starting game, PRESS CTRL-C to exit

cd /d "%VALHEIM_DIR%"
valheim.exe --doorstop-enable true --doorstop-target-assembly "%MODPATH%\BepInEx\core\BepInEx.Preloader.dll"

pause