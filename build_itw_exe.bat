@echo off
setlocal

set "ITW_BUILD_SCRIPT=%~dp0build_itw_exe.ps1"

if not exist "%ITW_BUILD_SCRIPT%" (
    echo ERROR: Cannot find "%ITW_BUILD_SCRIPT%".
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -File "%ITW_BUILD_SCRIPT%" %*

set "ITW_BUILD_EXIT_CODE=%ERRORLEVEL%"
exit /b %ITW_BUILD_EXIT_CODE%
