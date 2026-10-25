@echo off
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
echo =======================================================
echo      TIEN TRINH CAI GOI NGON NGU CHO WINDOWS 10/11
echo =======================================================
echo  Vui long chon ngon ngu ban muon xu ly:
echo.
echo   [1] Tieng Viet (vi-VN)         [2] Tieng Anh - My (en-US)
echo   [3] Tieng Anh - Anh (en-GB)    [4] Tieng Nhat Ban (ja-JP)
echo   [5] Tieng Han Quoc (ko-KR)     [6] Tieng Trung - Gian (zh-CN)
echo   [7] Tieng Trung - Phon (zh-TW) [8] Tieng Phap (fr-FR)
echo   [9] Tieng Duc (de-DE)          [10] Tieng Nga (ru-RU)
echo   [11] Tieng Tay Ban Nha (es-ES) [12] Tieng Bo Dao Nha (pt-BR)
echo   [13] Tieng Y (it-IT)           [14] Tieng Thai Lan (th-TH)
echo   [15] Tieng Indonesia (id-ID)   [16] Tieng An Do (hi-IN)
echo.
echo   [0] Thoat chuong trinh
echo =======================================================
echo.

set "CHOICE="
set /p CHOICE="Nhap lua chon cua ban (0-16): "

if "%CHOICE%"=="0" exit

if "%CHOICE%"=="1" set "LANG_CODE=vi-VN" & set "HEX_ID=042a" & goto :CHOOSE_METHOD
if "%CHOICE%"=="2" set "LANG_CODE=en-US" & set "HEX_ID=0409" & goto :CHOOSE_METHOD
if "%CHOICE%"=="3" set "LANG_CODE=en-GB" & set "HEX_ID=0809" & goto :CHOOSE_METHOD
if "%CHOICE%"=="4" set "LANG_CODE=ja-JP" & set "HEX_ID=0411" & goto :CHOOSE_METHOD
if "%CHOICE%"=="5" set "LANG_CODE=ko-KR" & set "HEX_ID=0412" & goto :CHOOSE_METHOD
if "%CHOICE%"=="6" set "LANG_CODE=zh-CN" & set "HEX_ID=0804" & goto :CHOOSE_METHOD
if "%CHOICE%"=="7" set "LANG_CODE=zh-TW" & set "HEX_ID=0404" & goto :CHOOSE_METHOD
if "%CHOICE%"=="8" set "LANG_CODE=fr-FR" & set "HEX_ID=040c" & goto :CHOOSE_METHOD
if "%CHOICE%"=="9" set "LANG_CODE=de-DE" & set "HEX_ID=0407" & goto :CHOOSE_METHOD
if "%CHOICE%"=="10" set "LANG_CODE=ru-RU" & set "HEX_ID=0419" & goto :CHOOSE_METHOD
if "%CHOICE%"=="11" set "LANG_CODE=es-ES" & set "HEX_ID=0c0a" & goto :CHOOSE_METHOD
if "%CHOICE%"=="12" set "LANG_CODE=pt-BR" & set "HEX_ID=0416" & goto :CHOOSE_METHOD
if "%CHOICE%"=="13" set "LANG_CODE=it-IT" & set "HEX_ID=0410" & goto :CHOOSE_METHOD
if "%CHOICE%"=="14" set "LANG_CODE=th-TH" & set "HEX_ID=041e" & goto :CHOOSE_METHOD
if "%CHOICE%"=="15" set "LANG_CODE=id-ID" & set "HEX_ID=0421" & goto :CHOOSE_METHOD
if "%CHOICE%"=="16" set "LANG_CODE=hi-IN" & set "HEX_ID=0439" & goto :CHOOSE_METHOD
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
echo [Buoc 5] Dang dong bo va nap ban phim nhap lieu...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$List = New-WinUserLanguageList -Language %LANG_CODE%; if ('%LANG_CODE%' -ne 'en-US') { $List.Add('en-US') }; Set-WinUserLanguageList -LanguageList $List -Force" >nul 2>&1

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
