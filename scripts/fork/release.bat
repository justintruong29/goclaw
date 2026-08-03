@echo off
REM release.bat - tao tag phat hanh cho fork va day len de CI dung anh Docker.
REM
REM Quy uoc ten:  fork-v^<tag-upstream-dev^>-^<YYYYMMDD^>
REM   vi du:      fork-v3.15.0-beta.188-20260803
REM Trung ngay thi tu them hau to .2 .3 ...
REM Tien to fork- tach han khoi ho tag v*-beta.NNN cua upstream nen khong dung nhau,
REM va nhin tag la biet ngay ban do dung tren nen upstream nao, ngay nao.
setlocal enabledelayedexpansion
call "%~dp0_common.bat"
if errorlevel 1 exit /b 1
cd /d "!REPO!"

for /f %%b in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%b
if not "!BRANCH!"=="release" (
  echo [LOI] Dang o nhanh !BRANCH!. Phat hanh phai dung tu nhanh release.
  exit /b 1
)

for /f %%i in ('git status --porcelain') do (
  echo [LOI] Cay lam viec chua sach. Commit hoac stash truoc.
  exit /b 1
)

git fetch origin
if errorlevel 1 exit /b 1
git fetch upstream --tags
if errorlevel 1 exit /b 1

REM Tag phai tro dung vao thu da nam tren origin/release, khong phai commit local.
for /f %%i in ('git rev-parse HEAD') do set LOCAL=%%i
for /f %%i in ('git rev-parse origin/release') do set REMOTE=%%i
if not "!LOCAL!"=="!REMOTE!" (
  echo [LOI] release local va origin/release khac nhau. Push hoac pull truoc khi tag.
  exit /b 1
)

for /f %%i in ('git describe --tags --abbrev^=0 upstream/dev') do set BASE=%%i
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set TODAY=%%i

set TAG=fork-!BASE!-!TODAY!
set N=1
:findfree
git rev-parse -q --verify "refs/tags/!TAG!" >nul
if not errorlevel 1 (
  set /a N+=1
  set TAG=fork-!BASE!-!TODAY!.!N!
  goto :findfree
)

echo.
echo Nen upstream : !BASE!
echo Tag phat hanh: !TAG!
echo Commit       : !LOCAL!
echo.
set /p OK="Tao va day tag nay? [y/N] "
if /i not "!OK!"=="y" (
  echo Huy.
  exit /b 1
)

git tag -a "!TAG!" -m "release !TAG!"
if errorlevel 1 exit /b 1
git push origin "!TAG!"
if errorlevel 1 exit /b 1

echo.
echo Da day tag !TAG!. CI dang dung anh:
echo     ghcr.io/justintruong29/goclaw:!TAG!
echo.
echo Tren VPS, dat trong .env:
echo     GOCLAW_IMAGE=ghcr.io/justintruong29/goclaw:!TAG!
echo roi chay:  ./scripts/fork/deploy.sh
endlocal
