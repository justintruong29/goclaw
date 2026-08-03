@echo off
REM sync.bat - dong bo upstream vao fork (chay hang tuan, 1 nguoi phu trach).
REM   1. fetch upstream
REM   2. day upstream/dev vao origin/dev bang fast-forward (mirror thuan)
REM   3. merge origin/dev vao release
REM Khong bao gio force-push. Neu buoc 2 that bai => co commit la tren dev.
setlocal
cd /d "%~dp0..\.."

git rev-parse --verify upstream/dev >nul 2>&1
if errorlevel 1 (
  echo [LOI] Chua co remote 'upstream'. Chay:
  echo     git remote add upstream https://github.com/nextlevelbuilder/goclaw.git
  exit /b 1
)

REM Cay lam viec phai sach truoc khi merge, neu khong merge se de lai trang thai roi.
for /f %%i in ('git status --porcelain') do (
  echo [LOI] Cay lam viec dang co thay doi chua commit. Commit hoac stash truoc.
  exit /b 1
)

echo.
echo === 1/3 Fetch upstream ===
git fetch upstream --tags
if errorlevel 1 exit /b 1
git fetch origin
if errorlevel 1 exit /b 1

echo.
echo === 2/3 Cap nhat mirror origin/dev ===
git push origin upstream/dev:dev
if errorlevel 1 (
  echo.
  echo [LOI] Push len dev that bai - gan nhu chac chan vi khong fast-forward,
  echo       tuc co ai do commit thang len dev. KHONG dung --force.
  echo       Chuyen commit do sang nhanh fix/* roi bao nguoi phu trach repo.
  exit /b 1
)
git fetch origin
if errorlevel 1 exit /b 1

echo.
echo === 3/3 Merge dev vao release ===
git checkout release
if errorlevel 1 exit /b 1
git pull --ff-only origin release
if errorlevel 1 exit /b 1
git merge --no-ff origin/dev
if errorlevel 1 (
  echo.
  echo [CONFLICT] Sua file bi xung dot, roi:
  echo     git add ^<file^>  ^&^&  git commit
  echo     scripts\fork\check.bat
  echo     git push origin release
  echo.
  echo Meo: neu upstream da tu sua cho do roi thi lay ban upstream
  echo      ^(git checkout --theirs ^<file^>^) va bo patch rieng di.
  exit /b 1
)

echo.
echo === Xong. Patch rieng con lai tren release: ===
git log --oneline origin/dev..HEAD
echo.
echo Buoc tiep theo:  scripts\fork\check.bat  roi  git push origin release
endlocal
