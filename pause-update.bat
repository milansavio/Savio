@echo OFF
set "params=%*"
cd /d "%~dp0" && ( if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs" ) && fsutil dirty query %systemdrive% 1>nul 2>nul || (  echo Set UAC = CreateObject^("Shell.Application"^) : UAC.ShellExecute "cmd.exe", "/k cd ""%~sdp0"" && %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs" && "%temp%\getadmin.vbs" && exit /B )
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v FlightSettingsMaxPauseDays /t REG_DWORD /d 7296 /f

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseFeatureUpdatesStartTime /t REG_SZ /d "2024-05-08T03:36:56Z" /f

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseFeatureUpdatesEndTime /t REG_SZ /d "2080-04-27T03:36:56Z" /f

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseQualityUpdatesStartTime /t REG_SZ /d "2024-05-08T03:36:56Z" /f

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseQualityUpdatesEndTime /t REG_SZ /d "2080-04-27T03:36:56Z" /f

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseUpdatesStartTime /t REG_SZ /d "2024-05-08T03:36:56Z" /f

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseUpdatesExpiryTime /t REG_SZ /d "2080-04-27T03:36:56Z" /f
echo Pause to 2080.
pause
exit
