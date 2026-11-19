@echo off
setlocal EnableExtensions
rem Usage: build-win-x64.cmd WORK_ROOT [--resume]
if "%~1"=="" (echo Usage: %~nx0 WORK_ROOT [--resume]>&2 & exit /b 2)
set "ROOT=%~f1"
set "DEPOT=%ROOT%\depot_tools"
set "SRC=%ROOT%\download\chromium\src"
set "CEF=%SRC%\cef"
set "CEF_PIN=abc1ece6a66997894c4c953ed24937603fbd74b4"
set "CHROMIUM_PIN=e7b998fb3cd79ff00dbc0067421dc6ec118892a8"
set "DEPOT_PIN=f4fadaf6a5ba1bced9d3d9021060667b563bf583"
if not defined VSDEVCMD set "VSDEVCMD=%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (echo Set VSDEVCMD to the Visual Studio 2022 VsDevCmd.bat path.>&2 & exit /b 2)
if not exist "%DEPOT%\python3.bat" (echo Install depot_tools at "%DEPOT%" and checkout %DEPOT_PIN%.>&2 & exit /b 2)
call "%VSDEVCMD%" -arch=amd64 -host_arch=amd64
if errorlevel 1 exit /b 1
set "PATH=%DEPOT%;%PATH%"
if defined GIT_USR_BIN set "PATH=%GIT_USR_BIN%;%PATH%"
set "DEPOT_TOOLS_WIN_TOOLCHAIN=0"
set "DEPOT_TOOLS_UPDATE=0"
set "CEF_USE_GN=1"
set "GYP_MSVS_VERSION=2022"
set "GN_OUT_CONFIGS=Release_GN_x64"
set "GN_DEFINES=is_debug=false is_official_build=false symbol_level=1 dcheck_always_on=false dcheck_is_configurable=false proprietary_codecs=true ffmpeg_branding=Chrome"
set "GIT_TERMINAL_PROMPT=0"
set "GCM_INTERACTIVE=Never"
if not defined CEF_JOBS set "CEF_JOBS=8"
for /f %%H in ('git -C "%DEPOT%" rev-parse HEAD') do set "ACTUAL=%%H"
if /I not "%ACTUAL%"=="%DEPOT_PIN%" (echo depot_tools checkout does not match pinned revision.>&2 & exit /b 1)
if /I "%~2"=="--resume" goto check_pins
if not exist "%ROOT%\cef\tools\automate\automate-git.py" (echo Clone obsproject/cef at %CEF_PIN% into "%ROOT%\cef".>&2 & exit /b 2)
for /f %%H in ('git -C "%ROOT%\cef" rev-parse HEAD') do set "ACTUAL=%%H"
if /I not "%ACTUAL%"=="%CEF_PIN%" (echo CEF seed checkout does not match pinned revision.>&2 & exit /b 1)
call "%DEPOT%\python3.bat" "%ROOT%\cef\tools\automate\automate-git.py" --download-dir="%ROOT%\download" --depot-tools-dir="%DEPOT%" --url=https://github.com/obsproject/cef.git --branch=7871 --checkout=%CEF_PIN% --chromium-checkout=refs/tags/150.0.7871.287 --chromium-url=https://github.com/chromium/chromium.git --force-config --no-chromium-history --no-depot-tools-update --force-patch-update --x64-build --no-build --no-distrib
if errorlevel 1 exit /b 1
:check_pins
for /f %%H in ('git -C "%CEF%" rev-parse HEAD') do set "ACTUAL=%%H"
if /I not "%ACTUAL%"=="%CEF_PIN%" (echo CEF checkout does not match pinned revision.>&2 & exit /b 1)
for /f %%H in ('git -C "%SRC%" rev-parse HEAD') do set "ACTUAL=%%H"
if /I not "%ACTUAL%"=="%CHROMIUM_PIN%" (echo Chromium checkout does not match pinned revision.>&2 & exit /b 1)
if /I "%~2"=="--resume" goto build
pushd "%CEF%" || exit /b 1
call "%DEPOT%\python3.bat" tools\gclient_hook.py
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" exit /b %RC%
:build
pushd "%SRC%" || exit /b 1
call autoninja -j %CEF_JOBS% -C out\Release_GN_x64 cefclient bootstrap bootstrapc
set "RC=%errorlevel%"
popd
exit /b %RC%
