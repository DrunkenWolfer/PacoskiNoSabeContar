@echo off
setlocal

cd /d "f:\Bnet\World of Warcraft\_retail_\Interface\AddOns\PacoskiNoSabeContar"

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Esta carpeta no es un repositorio Git.
  pause
  exit /b 1
)

set "MSG=%~1"
if "%MSG%"=="" (
  set "MSG=Update addon files"
)

git status --porcelain >nul 2>&1
for /f %%i in ('git status --porcelain ^| find /c /v ""') do set CHANGES=%%i
if "%CHANGES%"=="0" (
  echo [INFO] No hay cambios para commit.
  pause
  exit /b 0
)

echo [INFO] Añadiendo cambios...
git add .
if errorlevel 1 (
  echo [ERROR] Fallo en git add.
  pause
  exit /b 1
)

echo [INFO] Creando commit...
git commit -m "%MSG%"
if errorlevel 1 (
  echo [ERROR] Fallo en git commit.
  pause
  exit /b 1
)

echo [INFO] Haciendo push...
git push
if errorlevel 1 (
  echo [ERROR] Fallo en git push.
  pause
  exit /b 1
)

echo [OK] Commit y push completados.
pause
exit /b 0
