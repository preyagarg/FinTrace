@echo off
REM ================================================================
REM  FinTrace - start the app (Windows)
REM  Double-click this file. Keep the black window open while using
REM  the app; close it (or press Ctrl+C) to stop the server.
REM ================================================================
cd /d "%~dp0fintrace"

where uv >nul 2>nul
if errorlevel 1 (
    echo uv not found. Please run setup.bat first.
    pause
    exit /b 1
)

echo Starting FinTrace on http://localhost:5000 ...
REM open the browser 3 seconds later, once the server is up
start "" /min cmd /c "timeout /t 3 /nobreak >nul & start http://localhost:5000"
uv run python app.py
pause
