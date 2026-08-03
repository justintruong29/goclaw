@echo off
REM hotfix.bat - va loi production gap. Cat tu origin/release vi do la thu
REM dang chay tren VPS, khong phai dev.
REM
REM Dung:  hotfix.bat socket-timeout
setlocal
call "%~dp0_common.bat"
if errorlevel 1 exit /b 1
cd /d "%REPO%"

if "%~1"=="" (
  echo Dung: hotfix.bat ^<mo-ta^>
  echo   vi du: hotfix.bat socket-timeout
  exit /b 1
)

git fetch origin
if errorlevel 1 exit /b 1

git checkout -b "hotfix/%~1" origin/release
if errorlevel 1 exit /b 1

echo.
echo Da tao nhanh hotfix/%~1 tren nen origin/release.
echo Sau khi sua xong:
echo     check.bat
echo     git push -u origin hotfix/%~1
echo     gh pr create --base release --fill
echo     release.bat          (tao tag + trien khai)
echo.
echo Dung quen dua fix nay len upstream:
echo     git checkout -b fix/%~1 origin/dev
echo     git cherry-pick ^<sha^>
echo     gh pr create --repo nextlevelbuilder/goclaw --base dev --fill
endlocal
