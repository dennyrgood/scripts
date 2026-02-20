@echo off
:: Check if we are actually in a git repo before starting
if not exist ".git\" (
    echo [ERROR] This folder is not a Git repository.
    pause
    exit /b
)

echo Syncing repository in: %cd%

git add .

:: Only commit if there are actually changes to save
git diff-index --quiet HEAD || git commit -m "Sync: %date% %time%"

:: Pull the online changes
git pull --rebase

:: Push your local changes
git push origin main

echo ---------------------------------------
git status
echo ---------------------------------------
pause