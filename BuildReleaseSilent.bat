@echo off
setlocal

cd /d "f:\Bnet\World of Warcraft\_retail_\Interface\AddOns\PacoskiNoSabeContar"

if not exist "Release\PacoskiNoSabeContar" mkdir "Release\PacoskiNoSabeContar"

copy /Y "PacoskiNoSabeContar.lua" "Release\PacoskiNoSabeContar\" >nul
copy /Y "PacoskiNoSabeContar.toc" "Release\PacoskiNoSabeContar\" >nul
copy /Y "Changelog.txt" "Release\PacoskiNoSabeContar\" >nul

echo [OK] Silent release build completado:
echo      Release\PacoskiNoSabeContar
exit /b 0
