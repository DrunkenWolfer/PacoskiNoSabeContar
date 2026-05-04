@echo off
setlocal EnableDelayedExpansion

cd /d "f:\Bnet\World of Warcraft\_retail_\Interface\AddOns\PacoskiNoSabeContar"

echo [CHECK] Verificando metadatos de release...

findstr /B /C:"## Version:" "PacoskiNoSabeContar.toc" >nul
if errorlevel 1 (
  echo [WARN] No hay linea "## Version:" en PacoskiNoSabeContar.toc
  echo        Recomendado: usar versionado semantico (ej. 1.0.1)
)

for /f "tokens=1 delims=:" %%a in ('findstr /N "^" "Changelog.txt"') do set LASTLINE=%%a
if "%LASTLINE%"=="" (
  echo [WARN] Changelog.txt parece vacio.
) else (
  set /a START=%LASTLINE%-5
  if !START! LSS 1 set START=1
  set HASDATE=
  for /f "tokens=1,* delims=:" %%a in ('findstr /N "^" "Changelog.txt"') do (
    if %%a GEQ !START! (
      echo %%b | findstr /R "^[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]$" >nul && set HASDATE=1
    )
  )
  if not defined HASDATE (
    echo [WARN] No se detecta fecha reciente al final de Changelog.txt
    echo        Recomendado: anadir entrada con formato YYYY-MM-DD
  )
)

if not exist "Release\PacoskiNoSabeContar" mkdir "Release\PacoskiNoSabeContar"

copy /Y "PacoskiNoSabeContar.lua" "Release\PacoskiNoSabeContar\" >nul
copy /Y "PacoskiNoSabeContar.toc" "Release\PacoskiNoSabeContar\" >nul
copy /Y "Changelog.txt" "Release\PacoskiNoSabeContar\" >nul

echo [OK] Carpeta de instalacion actualizada en:
echo      Release\PacoskiNoSabeContar
pause
