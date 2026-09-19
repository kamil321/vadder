@echo off
setlocal EnableExtensions
title Vadder

call "%~dp0update-mods.bat"
if errorlevel 1 (
    echo [Vadder] update-mods failed with code %errorlevel%.
    exit /b 1
)

call "%~dp0start-game.bat"
exit /b %errorlevel%