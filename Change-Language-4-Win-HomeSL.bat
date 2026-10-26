@echo off
:: Rong console de chu khong bi go dong khi keo cua so
mode con cols=170 lines=45
:: Giao dien cmd: nen trang, chu den
color F0
title Tools Thay Doi Ngon Ngu Windows - Windows Home Single Language by Savio
cls

:: ==========================================
:: TU DONG GOI QUYEN ADMINISTRATOR (ELEVATION)
:: ==========================================
:check_Permissions
    fsutil dirty query %systemdrive% >nul 2>&1
    if %errorlevel% == 0 (
        goto :gotAdmin
    ) else (
        goto :tryUAC
    )

:tryUAC
    echo Dang yeu cau quyen Administrator...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "cmd.exe", "/c ""%~s0""", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

:: ==========================================
:: BƯỚC 1: GIAO DIEN LUA CHON NGON NGU TRUOC
:: ==========================================
:MENU_LANG
cls
echo =====================================================================
echo      TIEN TRINH CAI GOI NGON NGU CHO WINDOWS 10/11
echo =====================================================================
echo  Vui long chon ngon ngu ban muon xu ly:
echo.
echo   [1] Tieng Viet (vi-VN)           ^|  [2] Tieng Anh - Anh (en-GB)
echo   [3] Tieng Anh - My (en-US)       ^|  [4] Tieng An Do (hi-IN)
echo   [5] Tieng Bo Dao Nha (pt-BR)     ^|  [6] Tieng Duc (de-DE)
echo   [7] Tieng Han Quoc (ko-KR)       ^|  [8] Tieng Indonesia (id-ID)
echo   [9] Tieng Nga (ru-RU)            ^|  [10] Tieng Nhat Ban (ja-JP)
echo   [11] Tieng Phap (fr-FR)          ^|  [12] Tieng Tay Ban Nha (es-ES)
echo   [13] Tieng Thai Lan (th-TH)      ^|  [14] Tieng Trung - Gian (zh-CN)
echo   [15] Tieng Trung - Phon (zh-TW)  ^|  [16] Tieng Y (it-IT)
echo.
echo   [0] Thoat chuong trinh
echo =====================================================================
echo.

set "CHOICE="
set /p CHOICE="Nhap lua chon cua ban (0-16): "

if "%CHOICE%"=="0" exit

if "%CHOICE%"=="1" set "LANG_CODE=vi-VN" & set "HEX_ID=042a" & goto :CHOOSE_METHOD
if "%CHOICE%"=="2" set "LANG_CODE=en-GB" & set "HEX_ID=0809" & goto :CHOOSE_METHOD
if "%CHOICE%"=="3" set "LANG_CODE=en-US" & set "HEX_ID=0409" & goto :CHOOSE_METHOD
if "%CHOICE%"=="4" set "LANG_CODE=hi-IN" & set "HEX_ID=0439" & goto :CHOOSE_METHOD
if "%CHOICE%"=="5" set "LANG_CODE=pt-BR" & set "HEX_ID=0416" & goto :CHOOSE_METHOD
if "%CHOICE%"=="6" set "LANG_CODE=de-DE" & set "HEX_ID=0407" & goto :CHOOSE_METHOD
if "%CHOICE%"=="7" set "LANG_CODE=ko-KR" & set "HEX_ID=0412" & goto :CHOOSE_METHOD
if "%CHOICE%"=="8" set "LANG_CODE=id-ID" & set "HEX_ID=0421" & goto :CHOOSE_METHOD
if "%CHOICE%"=="9" set "LANG_CODE=ru-RU" & set "HEX_ID=0419" & goto :CHOOSE_METHOD
if "%CHOICE%"=="10" set "LANG_CODE=ja-JP" & set "HEX_ID=0411" & goto :CHOOSE_METHOD
if "%CHOICE%"=="11" set "LANG_CODE=fr-FR" & set "HEX_ID=040c" & goto :CHOOSE_METHOD
if "%CHOICE%"=="12" set "LANG_CODE=es-ES" & set "HEX_ID=0c0a" & goto :CHOOSE_METHOD
if "%CHOICE%"=="13" set "LANG_CODE=th-TH" & set "HEX_ID=041e" & goto :CHOOSE_METHOD
if "%CHOICE%"=="14" set "LANG_CODE=zh-CN" & set "HEX_ID=0804" & goto :CHOOSE_METHOD
if "%CHOICE%"=="15" set "LANG_CODE=zh-TW" & set "HEX_ID=0404" & goto :CHOOSE_METHOD
if "%CHOICE%"=="16" set "LANG_CODE=it-IT" & set "HEX_ID=0410" & goto :CHOOSE_METHOD
goto :MENU_LANG

:: ==========================================
:: BƯỚC 2: CHON PHUONG THUC CAI DAT CHO NGON NGU DA CHON
:: ==========================================
:CHOOSE_METHOD
cls
echo =======================================================
echo          CHON PHUONG THUC CAI DAT NGON NGU
echo =======================================================
echo  Ngon ngu dang chon: %LANG_CODE%
echo -------------------------------------------------------
echo   [1] Cai day du (Ca Ngon ngu hien thi va Bo go)
echo   [2] Chi cai Ngon ngu hien thi (Display Language)
echo   [3] Chi cai Bo go ban phim (Input Keyboard)
echo.
echo   [B] Quay lai chon lai ngon ngu
echo   [0] Thoat chuong trinh
echo =======================================================
echo.
set "METHOD="
set /p METHOD="Nhap phuong thuc ban muon chon (0-3 / B): "

if /i "%METHOD%"=="B" goto :MENU_LANG
if "%METHOD%"=="0" exit

if "%METHOD%"=="1" goto :INSTALL_FULL
if "%METHOD%"=="2" goto :INSTALL_LANG_ONLY
if "%METHOD%"=="3" goto :INSTALL_INPUT_ONLY
goto :CHOOSE_METHOD

:: ------------------------------------------
:: OPTION 1: CAI DAY DU (LANGUAGE + BO GO)
:: ------------------------------------------
:INSTALL_FULL
cls
echo =======================================================
echo  TIEN TRINH DANG DUOC THUC THI - DUNG TAT TOOLS NGANG
echo =======================================================
echo Ngon ngu dich: %LANG_CODE% (Cai dat day du)
echo.
echo [Buoc 1] Dang tai va nap day du goi tinh nang (MUI + Keyboard)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name 'Language.Basic~~~%LANG_CODE%~~~0.0.1.0' -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Install-Language -Language %LANG_CODE% -ErrorAction SilentlyContinue } catch {}"
call :CHECK_LPCAB
if %errorlevel% neq 0 (
    pause >nul
    goto :MENU_LANG
)

call :APPLY_DISPLAY

goto :ACTIVATE_BAR

:: ------------------------------------------
:: OPTION 2: CHI CAI LANGUAGE (DISPLAY UI ONLY)
:: ------------------------------------------
:INSTALL_LANG_ONLY
cls
echo =======================================================
echo  TIEN TRINH DANG DUOC THUC THI - DUNG TAT TOOLS NGANG
echo =======================================================
echo Ngon ngu dich: %LANG_CODE% (Chi ngon ngu hien thi)
echo.
echo [Buoc 1] Dang tai va nap duy nhat goi ngon ngu hien thi (MUI)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Install-Language -Language %LANG_CODE% -ExcludeFeatures -ErrorAction SilentlyContinue } catch {}"
call :CHECK_LPCAB
if %errorlevel% neq 0 (
    pause >nul
    goto :MENU_LANG
)

call :APPLY_DISPLAY

goto :FINALIZE

:: ------------------------------------------
:: OPTION 3: CHI CAI BO GO (KEYBOARD INPUT ONLY)
:: ------------------------------------------
:INSTALL_INPUT_ONLY
cls
echo =======================================================
echo  TIEN TRINH DANG DUOC THUC THI - DUNG TAT TOOLS NGANG
echo =======================================================
echo Ngon ngu dich: %LANG_CODE% (Chi bo go ban phim)
echo.
echo [Buoc 1] Dang tai va nap thanh phan bo go (Basic Input)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name 'Language.Basic~~~%LANG_CODE%~~~0.0.1.0' -ErrorAction SilentlyContinue"
echo.
echo [Kiem tra] Dang xac nhan goi ngon ngu %LANG_CODE% da duoc cai dat...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cap = Get-WindowsCapability -Online -Name 'Language.Basic~~~%LANG_CODE%~~~0.0.1.0' -ErrorAction SilentlyContinue; if ($null -eq $cap -or $cap.State -ne 'Installed') { exit 1 }"
if %errorlevel% neq 0 (
    echo.
    echo [CANH BAO] Goi ngon ngu %LANG_CODE% CHUA duoc cai dat thanh cong!
    echo Nguyen nhan thuong gap: khong co mang, Windows Update dang bi tam dung,
    echo hoac ban Windows nay khong ho tro lenh Install-Language.
    echo Tool se khong doi ngon ngu hien thi khi goi chua co. Hay kiem tra lai roi chay lai.
    pause >nul
    goto :MENU_LANG
)

echo.
echo [Buoc 2] Dang them layout ban phim vao danh sach cua User hien tai...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$List = Get-WinUserLanguageList; if (!($List.LanguageTag -contains '%LANG_CODE%')) { $List.Add('%LANG_CODE%') }; Set-WinUserLanguageList -LanguageList $List -Force" >nul 2>&1

goto :ACTIVATE_BAR

:: ==========================================
:: KICH HOAT THANH CHUYEN DOI LAYOUT BAN PHIM
:: ==========================================
:ACTIVATE_BAR
echo.
echo [Buoc Ke] Dang kich hoat thanh ngon ngu nhap lieu tai System Tray...
reg add "HKCU\Software\Microsoft\CTF\LangBar" /v "ShowStatus" /t REG_DWORD /d 4 /f >nul
reg add "HKCU\Software\Microsoft\CTF\LangBar" /v "ExtraIconsOnTaskbar" /t REG_DWORD /d 1 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "ctfmon" /t REG_SZ /d "C:\Windows\System32\ctfmon.exe" /f >nul
start "" "C:\Windows\System32\ctfmon.exe"

:: ==========================================
:: KET THUC TIEN TRINH & HOI REBOOT
:: ==========================================
:FINALIZE
echo.
echo =======================================================
echo          [ DA THUC THI CAI NGON NGU HOAN TAT ]
echo =======================================================
echo.
echo Note: De xoa hoan toan cache hoac ap dung giao dien moi, 
echo ban nen lam moi lai he thong bang cach RESTART.
echo.
set "REBOOT="
set /p REBOOT="Ban co muon KHOI DONG LAI MAY TINH ngay bay gio khong? (Y/N): "

if /i "%REBOOT%"=="Y" (
    echo Dang khoi dong lai may tinh sau 5 giay...
    shutdown /r /t 5 /f
    exit
) else (
    echo.
    echo Vui long chu dong Re-log hoac Restart de ap dung thay doi!
    pause >nul
)
goto :MENU_LANG


:: ==========================================
:: KIEM TRA GOI NGON NGU + FALLBACK UUPDUMP
:: ==========================================
:CHECK_LPCAB
echo.
echo [Kiem tra] Dang xac nhan goi ngon ngu %LANG_CODE% da duoc cai dat...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$l = Get-InstalledLanguage -Language %LANG_CODE% -ErrorAction SilentlyContinue; if ($null -eq $l -or (($l.LanguagePacks -join ' ') -notmatch 'LpCab|LXP')) { exit 1 }"
if %errorlevel% == 0 exit /b 0
echo.
echo Tai tu Windows Update khong thanh cong - Ban co muon tai ve tu UUPDump? (Y/N)
set "UUPCHOICE="
set /p UUPCHOICE="Nhap lua chon (Y/N): "
if /i not "%UUPCHOICE%"=="Y" (
    echo [LOI] Ban da huy tai tu UUPDump. Khong cai dat duoc goi ngon ngu %LANG_CODE%.
    exit /b 1
)
call :FALLBACK_UUPDUMP
if %errorlevel% == 0 exit /b 0
if %errorlevel% == 2 exit /b 2
echo [LOI] Tai tu UUPDump that bai. Khong cai dat duoc goi ngon ngu %LANG_CODE%.
exit /b 1

:FALLBACK_UUPDUMP
echo.
echo [UUPDump] Dang tai goi ngon ngu %LANG_CODE% tu UUPDump...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/milansavio/Savio/main/Install-UUPDumpLanguage.ps1' -OutFile '%TEMP%\Install-UUPDumpLanguage.ps1' -UseBasicParsing"
if %errorlevel% neq 0 (
    echo [LOI] Khong tai duoc script ho tro UUPDump.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\Install-UUPDumpLanguage.ps1" -Language %LANG_CODE%
if %errorlevel% == 2 (
    echo.
    echo [UUPDump] File ESD da duoc tai ve, tool giu nguyen file de ban convert sang CAB roi cai tay.
    echo Tool se khong doi ngon ngu hien thi khi goi chua co.
    del "%TEMP%\Install-UUPDumpLanguage.ps1" >nul 2>&1
    exit /b 2
)
if %errorlevel% neq 0 (
    echo [LOI] Script UUPDump chay khong thanh cong. File tam nam tai: %TEMP%\Install-UUPDumpLanguage.ps1
    exit /b 1
)
del "%TEMP%\Install-UUPDumpLanguage.ps1" >nul 2>&1
exit /b 0

:: ==========================================
:: AP DUNG NGON NGU HIEN THI (DUNG CHO OPTION 1 VA 2)
:: Nguyen tac: ngon ngu moi phai dung DAU danh sach ngon ngu cua User,
:: vi Windows lay ngon ngu dau danh sach (co goi da cai) lam ngon ngu hien thi.
:: Chi them vao cuoi danh sach thi en-US van dung dau va giao dien van tieng Anh.
:: ==========================================
:APPLY_DISPLAY
echo.
echo [Buoc 2] Dang ghi de ngon ngu hien thi he thong (Preferred UI)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-SystemPreferredUILanguage -Language %LANG_CODE%" >nul 2>&1

echo.
echo [Buoc 3] Dang can thiep Registry cho phan hien thi UI...
reg add "HKCU\Control Panel\International" /v "LocaleName" /t REG_SZ /d "%LANG_CODE%" /f >nul
reg add "HKCU\Control Panel\Desktop" /v "PreferredUILanguages" /t REG_MULTI_SZ /d "%LANG_CODE%" /f >nul

echo.
echo [Buoc 4] Dang ep thay doi ma vung Machine ID thanh %HEX_ID%...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "Default" /t REG_SZ /d "%HEX_ID%" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "InstallLanguage" /t REG_SZ /d "%HEX_ID%" /f >nul

echo.
echo [Buoc 5] Dang go bo roi them lai ngon ngu %LANG_CODE% len DAU danh sach (de Windows dang ky lai sach se, khac phuc loi Settings khong doi ngon ngu)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$List = Get-WinUserLanguageList; $tp = ('%LANG_CODE%' -split '-')[0]; $Targets = @($List | Where-Object { ($_.LanguageTag -split '-')[0] -eq $tp }); foreach ($t in $Targets) { $List.Remove($t) }; if ($List.Count -gt 0) { Set-WinUserLanguageList -LanguageList $List -Force }; Set-WinUILanguageOverride -Language %LANG_CODE%; $New = New-WinUserLanguageList -Language %LANG_CODE%; foreach ($l in $List) { $New.Add($l) }; Set-WinUserLanguageList -LanguageList $New -Force" >nul 2>&1
echo.
echo [Buoc 6] Dang dang ky lai goi LXP cho user hien tai (neu co)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$key = '%LANG_CODE%'.Replace('-','').ToLower(); $p = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*LanguageExperiencePack*' -and ($_.Name.Replace('-','').Replace('.','').ToLower() -like ('*' + $key + '*')) } | Select-Object -First 1; if ($null -ne $p) { Add-AppxPackage -Register -Path (Join-Path $p.InstallLocation 'AppxManifest.xml') -DisableDevelopmentMode -ErrorAction SilentlyContinue }" >nul 2>&1

echo.
echo.
echo [Buoc 7] Dang cap nhat goi LXP tu Microsoft Store (neu co ban moi, khong bat buoc)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$map = @{ 'vi-VN' = '9P0W68X0XZPT'; 'en-US' = '9PDSCC711RVF'; 'en-GB' = '9NT52VQ39BVN'; 'ja-JP' = '9N1W692FV4S1'; 'ko-KR' = '9N4TXPCVRNGF'; 'zh-CN' = '9NRMNT6GMZ70'; 'zh-TW' = '9PCJ4DHCQ1JQ'; 'fr-FR' = '9NHMG4BJKMDG'; 'de-DE' = '9P6CT0SLW589'; 'ru-RU' = '9NMJCX77QKPX'; 'es-ES' = '9NWVGWLHPB1Z'; 'pt-BR' = '9P8LBDM4FW35'; 'it-IT' = '9P8PQWNS6VJX'; 'th-TH' = '9MSTWFRL0LR4'; 'id-ID' = '9P4X3N4SDK8P'; 'hi-IN' = '9NZC3GRX8LD3' }; $id = $map['%LANG_CODE%']; if (($null -ne $id) -and (Get-Command winget -ErrorAction SilentlyContinue)) { winget install --id $id --exact --source msstore --accept-package-agreements --accept-source-agreements }" >nul 2>&1
echo.
echo [Buoc 8] Dang dong app Settings va xoa cache cua no (de app nap lai ngon ngu)...
taskkill /f /im SystemSettings.exe >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'Packages\windows.immersivecontrolpanel_cw5n1h2txyewy\LocalState') -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'Packages\windows.immersivecontrolpanel_cw5n1h2txyewy\TempState') -ErrorAction SilentlyContinue" >nul 2>&1
echo [Kiem tra] Dang xac nhan cac lop hien thi sau khi ap dung...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$list = Get-WinUserLanguageList; $first = $list[0].LanguageTag; $ovr = Get-WinUILanguageOverride; $sys = Get-SystemPreferredUILanguage; $fp = ($first -split '-')[0]; $op = ($ovr -split '-')[0]; $sp = ($sys -split '-')[0]; $tp = ('%LANG_CODE%' -split '-')[0]; $lp = Get-InstalledLanguage -Language %LANG_CODE% -ErrorAction SilentlyContinue; $hasLp = ($null -ne $lp -and (($lp.LanguagePacks -join ' ') -match 'LpCab|LXP')); Write-Host ('[Kiem tra] Goi hien thi: ' + $(if ($hasLp) { 'DA CAI' } else { 'CHUA CO' })); Write-Host ('[Kiem tra] Ngon ngu dau danh sach User: ' + $first); Write-Host ('[Kiem tra] WinUI Override: ' + $ovr); Write-Host ('[Kiem tra] System Preferred UI: ' + $sys); if (($fp -eq $tp) -and ($op -eq $tp) -and ($sp -eq $tp)) { Write-Host ('[Kiem tra] OK - Sau khi khoi dong lai, giao dien se hien thi bang %LANG_CODE%.') } else { Write-Host '[CANH BAO] Cac lop hien thi chua khop het - giao dien co the van hien thi ngon ngu cu sau khi khoi dong lai, hay kiem tra lai trong Settings.' }"
exit /b 0
