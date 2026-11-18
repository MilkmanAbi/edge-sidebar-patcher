@echo off
rem Double-click launcher: interactive profile picker.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0EdgeSidebarPatcher.ps1" %*
pause
