@echo off
rem FrED Motor Remote Experiments - double-click launcher.
rem Finds a Python (Anaconda, Miniconda, or PATH) and opens the app with no
rem console window. If the window never appears, run "python app.py" from a
rem console instead to see the error.
setlocal
cd /d "%~dp0"

set "PYW="

rem 1) common Anaconda / Miniconda install locations (pythonw = no console)
if exist "%USERPROFILE%\anaconda3\pythonw.exe"  set "PYW=%USERPROFILE%\anaconda3\pythonw.exe"
if not defined PYW if exist "%USERPROFILE%\miniconda3\pythonw.exe" set "PYW=%USERPROFILE%\miniconda3\pythonw.exe"
if not defined PYW if exist "%LOCALAPPDATA%\anaconda3\pythonw.exe" set "PYW=%LOCALAPPDATA%\anaconda3\pythonw.exe"
if not defined PYW if exist "%LOCALAPPDATA%\miniconda3\pythonw.exe" set "PYW=%LOCALAPPDATA%\miniconda3\pythonw.exe"
if not defined PYW if exist "C:\ProgramData\anaconda3\pythonw.exe" set "PYW=C:\ProgramData\anaconda3\pythonw.exe"

rem 2) any pythonw on PATH
if not defined PYW for /f "delims=" %%P in ('where pythonw 2^>nul') do if not defined PYW set "PYW=%%P"

if defined PYW (
    start "" "%PYW%" app.py
    exit /b 0
)

rem 3) fall back to console python (keeps a console window open with any errors)
for /f "delims=" %%P in ('where python 2^>nul') do (
    "%%P" app.py
    exit /b 0
)

echo Could not find Python. Install Anaconda or add python to your PATH.
pause
exit /b 1
