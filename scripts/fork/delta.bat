@echo off
REM delta.bat - xem phan khac biet rieng cua fork so voi upstream.
REM Danh sach nay cang ngan cang tot. Commit nao da duoc upstream merge thi
REM lan sync sau no tu bien mat khoi day.
setlocal
call "%~dp0_common.bat"
if errorlevel 1 exit /b 1
cd /d "%REPO%"

git fetch origin >nul 2>&1
git fetch upstream >nul 2>&1

echo === Patch rieng tren release (origin/dev..origin/release) ===
git log --oneline origin/dev..origin/release
echo.
echo === File bi dung toi ===
git diff --stat origin/dev...origin/release
echo.
echo === Mirror dev co dung bang upstream/dev khong ===
for /f %%i in ('git rev-parse origin/dev') do set A=%%i
for /f %%i in ('git rev-parse upstream/dev') do set B=%%i
if "%A%"=="%B%" (
  echo     DUNG - dev dang khop upstream/dev
) else (
  echo     LECH - chay sync.bat de dong bo
  git log --oneline origin/dev..upstream/dev
)
endlocal
