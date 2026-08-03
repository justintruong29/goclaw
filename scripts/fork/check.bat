@echo off
REM check.bat - bo kiem tra bat buoc truoc khi mo PR.
REM Giong het bo ma upstream chay trong CI, chay o day de khoi bi CI chan.
REM
REM Dung:  scripts\fork\check.bat        (chi Go)
REM        scripts\fork\check.bat web    (Go + web UI)
setlocal
cd /d "%~dp0..\.."

echo === go build ./... ===
go build ./...
if errorlevel 1 goto :fail

REM Ban desktop dung SQLite thay Postgres - upstream bat buoc phai compile duoc.
echo === go build -tags sqliteonly ./... ===
go build -tags sqliteonly ./...
if errorlevel 1 goto :fail

echo === go vet ./... ===
go vet ./...
if errorlevel 1 goto :fail

echo === go test -race ./... ===
go test -race -timeout=5m ./...
if errorlevel 1 goto :fail

if /i "%~1"=="web" (
  echo === ui/web: pnpm lint ^&^& pnpm build ===
  pushd ui\web
  call pnpm install --frozen-lockfile
  if errorlevel 1 (popd & goto :fail)
  call pnpm lint
  if errorlevel 1 (popd & goto :fail)
  call pnpm build
  if errorlevel 1 (popd & goto :fail)
  popd
)

echo.
echo === TAT CA XANH ===
endlocal
exit /b 0

:fail
echo.
echo === CO BUOC THAT BAI - sua truoc khi mo PR ===
endlocal
exit /b 1
