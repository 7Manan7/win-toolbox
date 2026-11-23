@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: Prefer powershell on PATH, fallback to default Windows PowerShell location
set "PS_BIN=powershell.exe"
where powershell.exe >nul 2>&1
if errorlevel 1 (
    if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
        set "PS_BIN=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    )
)

if /i "%~1"=="-gui" goto run_gui
if /i "%~1"=="--gui" goto run_gui
if /i "%~1"=="/gui" goto run_gui

"%PS_BIN%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script-Launcher.ps1" %*
goto end

:run_gui
shift
"%PS_BIN%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Toolbox-GUI.ps1" %*

:end
endlocal
