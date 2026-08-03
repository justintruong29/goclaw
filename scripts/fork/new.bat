@echo off
REM new.bat - tao nhanh viec moi, luon cat tu origin/dev.
REM Cat tu dev (khong phai release) de diff cua nhanh sach voi upstream,
REM dung lai duoc ngay khi mo PR nguoc len upstream.
REM
REM Dung:  new.bat fix/vault-tenant-path
REM        new.bat feat/telegram-alert
setlocal
call "%~dp0_common.bat"
if errorlevel 1 exit /b 1

REM Nhanh moi cat tu dev - ma dev khong chua scripts/fork - nen neu dang chay
REM ban trong repo thi lenh checkout duoi day se xoa chinh file nay giua chung.
if exist "%~dp0..\..\.git" (
  echo [LOI] Dang chay ban script nam TRONG repo.
  echo       Lenh checkout se xoa chinh file nay khi doi sang nhanh cat tu dev.
  echo       Chay scripts\fork\install.bat mot lan, roi dung ban da cai o ngoai.
  exit /b 1
)

cd /d "%REPO%"

if "%~1"=="" (
  echo Dung: new.bat ^<loai^>/^<mo-ta^>
  echo   loai: feat ^| fix ^| refactor ^| docs
  echo   vi du: new.bat fix/vault-tenant-path
  exit /b 1
)

echo %~1 | findstr /r "^feat/ ^fix/ ^refactor/ ^docs/" >nul
if errorlevel 1 (
  echo [LOI] Ten nhanh phai bat dau bang feat/ fix/ refactor/ hoac docs/
  echo       Va gap thi dung: hotfix.bat ^<mo-ta^>
  exit /b 1
)

git fetch origin
if errorlevel 1 exit /b 1

git checkout -b "%~1" origin/dev
if errorlevel 1 exit /b 1

echo.
echo Da tao nhanh %~1 tren nen origin/dev.
echo Xong viec:
echo     check.bat
echo     git push -u origin %~1
echo     gh pr create --base release --fill
endlocal
