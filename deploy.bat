@echo off
chcp 65001 >nul
echo ========================================
echo   The J-Frame - One-Click Deploy
echo ========================================
echo.

cd /d "%~dp0"

echo [1/3] ファイルをステージング...
"C:\Program Files\Git\bin\git.exe" add Gatekeeper.html GAS_Code.js Rules_v2026.md The_Logger_Background.mq5 The_Watcher.mq5

echo [2/3] コミット作成中...
for /f "tokens=1-5 delims=/ " %%a in ("%date%") do set d=%%a-%%b-%%c
for /f "tokens=1-2 delims=: " %%a in ("%time%") do set t=%%a:%%b
"C:\Program Files\Git\bin\git.exe" commit -m "Update %d% %t%"

echo [3/3] GitHubへプッシュ中...
"C:\Program Files\Git\bin\git.exe" push -u origin main

echo.
echo ========================================
echo   デプロイ完了！
echo   GitHub Pages は数分で自動更新されます。
echo ========================================
pause
