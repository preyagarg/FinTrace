@echo off
REM ================================================================
REM  FinTrace - one-time setup (Windows)
REM  Requires uv (https://docs.astral.sh/uv/). It installs the
REM  packages and creates your .env file.  (The DATABASE is set up
REM  separately in MySQL Workbench - see README.md.)
REM ================================================================
cd /d "%~dp0fintrace"

where uv >nul 2>nul
if errorlevel 1 (
    echo.
    echo ERROR: uv not found. Install it with:
    echo   powershell -c "irm https://astral.sh/uv/install.ps1 ^| iex"
    pause
    exit /b 1
)

echo.
echo [1/2] Installing packages with uv...
uv sync
if errorlevel 1 (
    echo.
    echo ERROR: package install failed. See README.md - Troubleshooting.
    pause
    exit /b 1
)

echo.
echo [2/2] Creating .env settings file...
if not exist .env (
    copy .env.example .env >nul
    echo Created fintrace\.env  - opening it now: set MYSQL_PASSWORD to YOUR MySQL root password, then save.
    notepad .env
) else (
    echo fintrace\.env already exists - keeping it.
)

echo.
echo ================================================================
echo  Setup complete!  Next: double-click run.bat
echo ================================================================
pause
