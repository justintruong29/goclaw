@echo off
REM _common.bat - xac dinh thu muc repo, dung chung cho cac script con lai.
REM
REM Vi sao can: nhanh feature cat tu origin/dev, ma dev la mirror thuan cua
REM upstream nen KHONG chua thu muc scripts/fork. Chay script tu trong repo se
REM tu xoa chinh no khi doi nhanh. Vi vay ban dung hang ngay phai nam NGOAI
REM repo (chay install.bat de cai ra), va no can biet repo o dau.
REM
REM Thu tu tim:
REM   1. bien moi truong GOCLAW_REPO
REM   2. file _repo-path.txt nam canh script (do install.bat ghi ra)
REM   3. thu muc cha 2 cap, khi script dang chay tu trong repo

set "REPO="

if defined GOCLAW_REPO set "REPO=%GOCLAW_REPO%"

if not defined REPO if exist "%~dp0_repo-path.txt" (
  for /f "usebackq delims=" %%p in ("%~dp0_repo-path.txt") do set "REPO=%%p"
)

if not defined REPO if exist "%~dp0..\..\.git" set "REPO=%~dp0..\.."

if not defined REPO (
  echo [LOI] Khong tim thay repo goclaw.
  echo       Cach 1: chay scripts\fork\install.bat tu trong repo
  echo       Cach 2: setx GOCLAW_REPO D:\duong\dan\toi\goclaw
  exit /b 1
)

if not exist "%REPO%\.git" (
  echo [LOI] "%REPO%" khong phai repo git.
  exit /b 1
)

exit /b 0
