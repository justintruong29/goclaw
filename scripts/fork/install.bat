@echo off
REM install.bat - cai bo script ra NGOAI repo.
REM
REM Bat buoc phai cai, khong phai tuy chon: nhanh feature cat tu origin/dev
REM (mirror thuan cua upstream) khong chua scripts/fork, nen chay tu trong repo
REM se hong ngay khi doi nhanh. Ban cai o ngoai thi doi nhanh kieu gi cung con.
REM
REM Dung:  scripts\fork\install.bat              -> cai vao ..\goclaw-tools
REM        scripts\fork\install.bat D:\tools     -> cai vao thu muc chi dinh
REM
REM Chay lai sau moi lan script duoc cap nhat tren nhanh release.
setlocal
cd /d "%~dp0..\.."
set "REPO=%CD%"

if "%~1"=="" (
  for %%d in ("%REPO%\..") do set "DEST=%%~fd\goclaw-tools"
) else (
  set "DEST=%~1"
)

if not exist "%DEST%" mkdir "%DEST%"
if errorlevel 1 (
  echo [LOI] Khong tao duoc thu muc "%DEST%".
  exit /b 1
)

copy /y "%REPO%\scripts\fork\*.bat" "%DEST%\" >nul
if errorlevel 1 (
  echo [LOI] Copy that bai.
  exit /b 1
)
del /q "%DEST%\install.bat" 2>nul

REM Ghi duong dan repo de _common.bat tim duoc, du script nam o dau.
> "%DEST%\_repo-path.txt" echo %REPO%

echo Da cai vao: %DEST%
echo.
dir /b "%DEST%"
echo.
echo Them thu muc do vao PATH de goi thang ten script:
echo     setx PATH "%%PATH%%;%DEST%"
endlocal
