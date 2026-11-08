@echo off
rem ============================================================
rem  SmartDorm - build unsigned HAP from command line
rem  Usage:  scripts\build-hap.bat   (run from anywhere)
rem
rem  IMPORTANT: DEVECO_SDK_HOME must point to the SDK ROOT
rem             (D:\DevEco Studio\sdk), NOT to sdk\default.
rem             hvigor-ohos-plugin resolves SDK components from
rem             this root; pointing at sdk\default makes it report
rem             "SDK component missing".
rem  NOTE: do not write logs or scripts into the "build" folder -
rem        hvigor deletes that folder on every build.
rem ============================================================
setlocal

set "DEVECO_SDK_HOME=D:\DevEco Studio\sdk"
set "HVIGOR_JS=D:\DevEco Studio\tools\hvigor\bin\hvigorw.js"

if not exist "%HVIGOR_JS%" (
  echo [ERROR] hvigor entry not found: %HVIGOR_JS%
  echo         Check your DevEco Studio installation path.
  exit /b 1
)

pushd "%~dp0.."

echo [INFO] project      = %CD%
echo [INFO] DEVECO_SDK_HOME = %DEVECO_SDK_HOME%
echo [INFO] hvigor        = %HVIGOR_JS%
echo [INFO] log           = %TEMP%\smartdorm-build.log

node "%HVIGOR_JS%" --mode module -p product=default assembleHap --no-daemon > "%TEMP%\smartdorm-build.log" 2>&1
set "RC=%ERRORLEVEL%"

popd

if not "%RC%"=="0" (
  echo [FAIL] hvigor exited with code %RC%
  echo        See %TEMP%\smartdorm-build.log
  exit /b %RC%
)

echo [OK] BUILD SUCCESSFUL
echo [OK] HAP: %~dp0..\entry\build\default\outputs\default\entry-default-unsigned.hap
endlocal
