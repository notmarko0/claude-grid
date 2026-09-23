@echo off
rem Claude Grid pokretac za Windows: otvori Windows Terminal -> WSL -> claude-grid.
rem Ako tvoja WSL distribucija nije "Ubuntu", promijeni ime ispod (vidi: wsl -l -v).
set DISTRO=Ubuntu
where wt >nul 2>nul
if %errorlevel%==0 (
  start "" wt.exe wsl.exe -d %DISTRO% --cd ~ -- bash -lc "~/.local/bin/claude-grid"
) else (
  wsl.exe -d %DISTRO% --cd ~ -- bash -lc "~/.local/bin/claude-grid"
)
