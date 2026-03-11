@echo off
if not exist ".git\" (
    echo [ERROR] This folder is not a Git repository.
    pause
    exit /b
)

echo Syncing repository in: %cd%

:: 1. Force back to main in case a previous sync failed mid-way
git checkout main

:: 2. Stage changes
git add .
    
:: 3. Only commit if there are actually changes
git diff-index --quiet HEAD || git commit -m "Sync: %date% %time%"

:: 4. Explicitly pull from origin main to avoid "Not on a branch" errors
git pull origin main --rebase

:: 5. Push local changes
git push origin main


echo ---------------------------------------
git status
echo ---------------------------------------
pause