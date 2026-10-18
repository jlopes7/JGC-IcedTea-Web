@echo off
setlocal DisableDelayedExpansion
rem Usage: Launch-ITW-EBS.cmd [JNLP-file] [ITW-install-folder] [capture-folder]
if /i "%~1"=="/?" goto usage
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
set "ITWD_JNLP=%USERPROFILE%\Downloads\frmservlet"

set "ITWD_INSTALL="
if exist "%~dp0bin\javaws.exe" set "ITWD_INSTALL=%~dp0"
if not defined ITWD_INSTALL if exist "%~dp0..\bin\javaws.exe" for %%I in ("%~dp0..") do set "ITWD_INSTALL=%%~fI"
if not defined ITWD_INSTALL if exist "%~dp0..\..\bin\javaws.exe" for %%I in ("%~dp0..\..") do set "ITWD_INSTALL=%%~fI"
if not defined ITWD_INSTALL set "ITWD_INSTALL=C:\Program Files\IcedTeaWeb\WebStart"

if not "%~1"=="" if not "%~1"=="-" set "ITWD_JNLP=%~f1"
if not "%~2"=="" if not "%~2"=="-" set "ITWD_INSTALL=%~2"
if not exist "%ITWD_JNLP%" (
  echo ERROR: The JNLP file does not exist: "%ITWD_JNLP%"
  exit /b 1
)
set "ITWD_LAUNCHER=%ITWD_INSTALL%\bin\javaws.exe"
if not exist "%ITWD_LAUNCHER%" (
  echo ERROR: bin\javaws.exe was not found in the specified installation folder.
  exit /b 1
)
set "ITWD_CAPTURE=%USERPROFILE%\ITW-EBS-Repro"
if not "%~3"=="" set "ITWD_CAPTURE=%~3"
if not exist "%ITWD_CAPTURE%" mkdir "%ITWD_CAPTURE%"
if not exist "%ITWD_CAPTURE%" (
  echo ERROR: Cannot create capture folder.
  exit /b 1
)
set "ITWD_LOG=%ITWD_CAPTURE%\javaws-console-%RANDOM%-%RANDOM%.log"
rem Scoped to this launcher and its child processes; preserve existing JVM options.
rem JAVA_TOOL_OPTIONS also reaches a JVM forked by ITW.
set "JAVA_TOOL_OPTIONS=%JAVA_TOOL_OPTIONS% -Ditw.ebs.trace=true"
rem Optional TLS-only reproduction: set ITW_DIAG_SSL=1 in this CMD session first.
if "%ITW_DIAG_SSL%"=="1" set "JAVA_TOOL_OPTIONS=%JAVA_TOOL_OPTIONS% -Djavax.net.debug=ssl,handshake"
echo Launching IcedTea-Web. Reproduce the problem, then close the Java application.
echo Console output: "%ITWD_LOG%"
> "%ITWD_LOG%" echo Started: %DATE% %TIME%
>> "%ITWD_LOG%" echo Launcher: "%ITWD_LAUNCHER%"
>> "%ITWD_LOG%" echo JNLP: "%ITWD_JNLP%"
rem START /WAIT is required for reliable waiting on a Windows GUI-subsystem EXE.
start "" /b /wait "%ITWD_LAUNCHER%" -verbose -J-Ditw.ebs.trace=true "%ITWD_JNLP%" >> "%ITWD_LOG%" 2>&1
set "ITWD_RC=%ERRORLEVEL%"
>> "%ITWD_LOG%" echo LauncherExitCode=%ITWD_RC%
>> "%ITWD_LOG%" echo Finished: %DATE% %TIME%
echo Launcher exit code: %ITWD_RC%
echo Collect this capture folder as argument 4 of Collect-ITW-EBS.cmd.
exit /b %ITWD_RC%
:usage
echo Usage: Launch-ITW-EBS.cmd [JNLP-file] [ITW-install-folder] [capture-folder]
echo Default JNLP: "%USERPROFILE%\Downloads\frmservlet"
echo Default ITW: "C:\Program Files\IcedTeaWeb\WebStart"
echo Omit arguments or use - to keep defaults.
exit /b 0
