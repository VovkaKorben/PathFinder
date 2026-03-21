@echo off
cd /d "%~dp0"
git status
git add .
set commit_message=Auto-commit %DATE% %TIME%
git commit -m "%commit_message%"
git push
pause