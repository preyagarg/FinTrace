@echo off
REM ================================================================
REM  FinTrace - one-time setup (Windows)
REM  Double-click this file, or run "setup.bat" in Command Prompt.
REM  It creates a Python virtual environment, installs the packages
REM  and creates your .env file.  (The DATABASE is set up separately
REM  in MySQL Workbench - see README.md, Step 2.)
REM ================================================================
cd /d "%~dp0fintrace"

echo.
echo [1/3] Creating Python virtual environment (venv)...
if not exist venv (
    python -m venv venv
    if errorlevel 1 (
        echo.
        echo ERROR: Python not found. Install Python 3.10 - 3.13 from python.org
        echo        and tick "Add Python to PATH" during installation.
        pause
        exit /b 1
    )
)

echo.
echo [2/3] Installing packages (Flask, MySQL driver, ...)...
call venv\Scripts\activate.bat
python -m pip install --upgrade pip >nul
pip install -r requirements.txt
if errorlevel 1 (
    echo.
    echo ERROR: package install failed. See README.md - Troubleshooting.
    pause
    exit /b 1
)

echo.
echo [3/3] Creating .env settings file...
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
