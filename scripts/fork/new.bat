@echo off
REM new.bat - tao nhanh viec moi, luon cat tu origin/dev.
REM Cat tu dev (khong phai release) de diff cua nhanh sach voi upstream,
REM dung lai duoc ngay khi mo PR nguoc len upstream.
REM
REM Dung:  scripts\fork\new.bat fix/vault-tenant-path
REM        scripts\fork\new.bat feat/telegram-alert
setlocal
cd /d "%~dp0..\.."

if "%~1"=="" (
  echo Dung: scripts\fork\new.bat ^<loai^>/^<mo-ta^>
  echo   loai: feat ^| fix ^| refactor ^| docs
  echo   vi du: scripts\fork\new.bat fix/vault-tenant-path
  exit /b 1
)

echo %~1 | findstr /r "^feat/ ^fix/ ^refactor/ ^docs/" >nul
if errorlevel 1 (
  echo [LOI] Ten nhanh phai bat dau bang feat/ fix/ refactor/ hoac docs/
  echo       Va gap thi dung: scripts\fork\hotfix.bat ^<mo-ta^>
  exit /b 1
)

git fetch origin
if errorlevel 1 exit /b 1

git checkout -b "%~1" origin/dev
if errorlevel 1 exit /b 1

echo.
echo Da tao nhanh %~1 tren nen origin/dev.
echo Xong viec:
echo     scripts\fork\check.bat
echo     git push -u origin %~1
echo     gh pr create --base release --fill
endlocal
