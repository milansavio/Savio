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
echo [Buoc 0] Dang kiem tra va tam mo Windows Update de tai goi (neu dang pause)...
call :PAUSE_LIFT
echo [Buoc 1] Dang tai va nap day du goi tinh nang (MUI + Keyboard)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name 'Language.Basic~~~%LANG_CODE%~~~0.0.1.0' -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Install-Language -Language %LANG_CODE% -ErrorAction SilentlyContinue } catch {}"
call :PAUSE_RESTORE
call :CHECK_LPCAB
if %errorlevel% neq 0 (
    echo.
    echo [CANH BAO] Chua xac nhan duoc goi ngon ngu %LANG_CODE% da cai dat, nhung van chay tiep lenh set ngon ngu theo yeu cau.
    call :PAUSE_RESTORE
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
echo [Buoc 0] Dang kiem tra va tam mo Windows Update de tai goi (neu dang pause)...
call :PAUSE_LIFT
echo [Buoc 1] Dang tai va nap duy nhat goi ngon ngu hien thi (MUI)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Install-Language -Language %LANG_CODE% -ExcludeFeatures -ErrorAction SilentlyContinue } catch {}"
call :PAUSE_RESTORE
call :CHECK_LPCAB
if %errorlevel% neq 0 (
    echo.
    echo [CANH BAO] Chua xac nhan duoc goi ngon ngu %LANG_CODE% da cai dat, nhung van chay tiep lenh set ngon ngu theo yeu cau.
    call :PAUSE_RESTORE
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
echo [Buoc 0] Dang kiem tra va tam mo Windows Update de tai goi (neu dang pause)...
call :PAUSE_LIFT
echo [Buoc 1] Dang tai va nap thanh phan bo go (Basic Input)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name 'Language.Basic~~~%LANG_CODE%~~~0.0.1.0' -ErrorAction SilentlyContinue"
call :PAUSE_RESTORE
echo.
echo [Kiem tra] Dang xac nhan goi ngon ngu %LANG_CODE% da duoc cai dat...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cap = Get-WindowsCapability -Online -Name 'Language.Basic~~~%LANG_CODE%~~~0.0.1.0' -ErrorAction SilentlyContinue; if ($null -eq $cap -or $cap.State -ne 'Installed') { exit 1 }"
if %errorlevel% neq 0 (
    call :PAUSE_RESTORE
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
set "UUPCHOICE=%UUPCHOICE: =%"
if /i "%UUPCHOICE%"=="Y" goto :UUP_YES
if /i "%UUPCHOICE%"=="YES" goto :UUP_YES
echo [LOI] Ban da huy tai tu UUPDump. Khong cai dat duoc goi ngon ngu %LANG_CODE%.
exit /b 1
:UUP_YES
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
set "IS_LIP=0"
if /i "%LANG_CODE%"=="vi-VN" set "IS_LIP=1"
if /i "%LANG_CODE%"=="hi-IN" set "IS_LIP=1"
if /i "%LANG_CODE%"=="id-ID" set "IS_LIP=1"
if "%IS_LIP%"=="1" echo [CANH BAO] %LANG_CODE% la ngon ngu dang LIP (ban dich mot phan).
if "%IS_LIP%"=="1" echo [CANH BAO] Tren Windows 10 cap nhat moi nhat, ung dung Settings co the van tieng Anh; cac ngon ngu day du (vd: ko-KR) khong bi anh huong.
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
echo.
call :CREATE_LANGLOCK_TASK
echo [Buoc 9] Da xong tac vu giu ngon ngu.
call :REMOVE_OTHER_LANGS
echo [Buoc 10] Da xong buoc go ngon ngu khac.
exit /b 0

:: ==========================================
:: TAM MO / KHOI PHUC PAUSE WINDOWS UPDATE
:: Chi dung trong luc tai goi ngon ngu (lua chon 1, 2, 3).
:: Neu may von khong pause thi khong lam gi, khong ep pause moi.
:: Khoi phuc chay ca khi tai thanh cong lan khi tai that bai.
:: ==========================================
:PAUSE_LIFT
powershell -NoProfile -ExecutionPolicy Bypass -Command "$k='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; $names=@('PauseFeatureUpdatesStartTime','PauseFeatureUpdatesEndTime','PauseQualityUpdatesStartTime','PauseQualityUpdatesEndTime','PauseUpdatesStartTime','PauseUpdatesExpiryTime'); $bak=Join-Path $env:TEMP 'SavioPauseBackup.txt'; $flag=Join-Path $env:TEMP 'SavioPauseWasPaused.txt'; $out=@(); foreach ($n in $names) { try { $v=(Get-ItemProperty -Path $k -Name $n -ErrorAction Stop).$n; $out+=($n+'='+$v) } catch { $out+=($n+'=') } }; $out | Out-File -FilePath $bak -Encoding ascii; $was='0'; if (Test-Path $bak) { try { $exp=[datetimeoffset]::Parse((Get-ItemProperty -Path $k -Name 'PauseUpdatesExpiryTime' -ErrorAction Stop).PauseUpdatesExpiryTime); if ($exp -gt [datetimeoffset]::UtcNow) { $was='1' } } catch {} }; $was | Out-File -FilePath $flag -Encoding ascii; if ($was -eq '1') { foreach ($n in $names) { Remove-ItemProperty -Path $k -Name $n -ErrorAction SilentlyContinue }; Write-Host '[Tam mo] Windows Update dang pause, da tam mo de tai goi.' }"
exit /b 0

:PAUSE_RESTORE
powershell -NoProfile -ExecutionPolicy Bypass -Command "$flag=Join-Path $env:TEMP 'SavioPauseWasPaused.txt'; if (!(Test-Path $flag)) { exit 0 }; $was=(Get-Content $flag -ErrorAction SilentlyContinue | Select-Object -First 1); if ($was -ne '1') { Remove-Item $flag -Force -ErrorAction SilentlyContinue; exit 0 }; $bak=Join-Path $env:TEMP 'SavioPauseBackup.txt'; $k='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; $found=Test-Path $bak; if ($found) { foreach ($line in (Get-Content $bak)) { if ($line -match '^([^=]+)=(.*)$') { $n=$matches[1]; $v=$matches[2]; if ($v -ne '') { New-ItemProperty -Path $k -Name $n -PropertyType String -Value $v -Force -ErrorAction SilentlyContinue } else { Remove-ItemProperty -Path $k -Name $n -ErrorAction SilentlyContinue } } } }; Remove-Item $flag -Force -ErrorAction SilentlyContinue; if ($found) { Remove-Item $bak -Force -ErrorAction SilentlyContinue; Write-Host '[Khoi phuc] Da khoi phuc lai trang thai pause nhu truoc.' } else { Write-Host '[Khoi phuc] Khong tim thay file sao luu pause, khong khoi phuc duoc.' }"
exit /b 0


:: ==========================================
:: TAC VU TASK SCHEDULER GIU NGON NGU SAU KHOI DONG (CHI CHO NGON NGU LIP)
:: Ly do: tren Win Home SL, Windows ghi de InstallLanguage va Default system UI
:: ve ngon ngu MUI goc (vd: th-TH) khi khoi dong, neu ngon ngu dich chi la LIP
:: (vi-VN, hi-IN, id-ID). Tac vu nay chay lai sau moi lan dang nhap, tre 30 giay,
:: de ghi de lai ID ngon ngu da chon. Tac vu TON TAI vinh vien cho den khi chon
:: mot ngon ngu MUI hoac xoa tay bang schtasks /Delete /TN "Savio-LangLock" /F
:: Chu y: day la thu nghiem, chua chac chan thang duoc co che ghi de khi boot.
:: Tac vu khong tu khoi dong lai may, khong tu dang xuat. Sau khi khoi dong lai,
:: hay dang xuat roi dang nhap lai de xem giao dien co doi khong, va kiem tra
:: file log C:\ProgramData\Savio\LangLock.log de biet tac vu co chay khong.
:: ==========================================
:CREATE_LANGLOCK_TASK
echo.
if "%IS_LIP%"=="0" (
    schtasks /Delete /TN "Savio-LangLock" /F >nul 2>&1
    echo [Buoc 9] Ngon ngu %LANG_CODE% la dang MUI/day du, khong can tac vu khoi dong. Da xoa tac vu cu (neu co).
    exit /b 0
)
echo [Buoc 9] Dang tao tac vu Task Scheduler de giu ngon ngu %LANG_CODE% sau moi lan khoi dong...
schtasks /Delete /TN "Savio-LangLock" /F >nul 2>&1
if not exist "C:\ProgramData\Savio" mkdir "C:\ProgramData\Savio" >nul 2>&1
echo @echo off > "C:\ProgramData\Savio\LangLock.bat"
echo reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "InstallLanguage" /t REG_SZ /d "%HEX_ID%" /f ^>nul 2^>^&1 >> "C:\ProgramData\Savio\LangLock.bat"
echo reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "Default" /t REG_SZ /d "%HEX_ID%" /f ^>nul 2^>^&1 >> "C:\ProgramData\Savio\LangLock.bat"
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-SystemPreferredUILanguage -Language %LANG_CODE%" ^>nul 2^>^&1 >> "C:\ProgramData\Savio\LangLock.bat"
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-WinUILanguageOverride -Language %LANG_CODE%" ^>nul 2^>^&1 >> "C:\ProgramData\Savio\LangLock.bat"
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "$L = Get-WinUserLanguageList; $N = New-WinUserLanguageList -Language %LANG_CODE%; foreach ($x in $L) { if ($x.LanguageTag -ne '%LANG_CODE%') { $N.Add($x) } }; Set-WinUserLanguageList -LanguageList $N -Force" ^>nul 2^>^&1 >> "C:\ProgramData\Savio\LangLock.bat"
echo powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Content -Path 'C:\ProgramData\Savio\LangLock.log' -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' LangLock %LANG_CODE% %HEX_ID%')" ^>nul 2^>^&1 >> "C:\ProgramData\Savio\LangLock.bat"
schtasks /Create /TN "Savio-LangLock" /TR "C:\ProgramData\Savio\LangLock.bat" /SC ONLOGON /DELAY 0000:30 /RL HIGHEST /F
if %errorlevel% neq 0 (
    echo [CANH BAO] Khong tao duoc tac vu Savio-LangLock. Hay chay tool voi quyen Admin roi thu lai.
    exit /b 0
)
schtasks /Query /TN "Savio-LangLock" >nul 2>&1
if %errorlevel% == 0 (
    echo [Buoc 9] Da tao tac vu Savio-LangLock: chay sau moi lan dang nhap, tre 30 giay, quyen cao nhat.
    echo [Buoc 9] File tac vu: C:\ProgramData\Savio\LangLock.bat - Log: C:\ProgramData\Savio\LangLock.log
    echo [Buoc 9] Sau khi khoi dong lai, hay dang xuat roi dang nhap lai, roi kiem tra log de biet tac vu co chay khong.
) else (
    echo [CANH BAO] Tac vu Savio-LangLock khong ton tai sau khi tao. Hay kiem tra Task Scheduler tay.
)
exit /b 0

:: ==========================================
:: GO CAC NGON NGU KHAC, CHI GIU TIENG ANH VA NGON NGU DA CHON (CHI CHO LIP)
:: Ly do: ngon ngu LIP (vi-VN, hi-IN, id-ID) can tieng Anh en-US lam goc day du.
:: Neu con goi MUI tieng Thai / tieng Trung trong may, khi khoi dong Windows se
:: roi ve goi MUI do thay vi hien thi LIP. Go het cac goi khac, chi giu en-US
:: va ngon ngu da chon, thi khong con goi nao khac de roi ve nua.
:: Chu y: day la thay doi he thong, can diem khoi phuc truoc. Go tung goi,
:: goi nao loi thi van go tiep goi sau, khong dung lai. Sau khi go xong se
:: ap dung lai ngon ngu da chon, roi moi khoi dong lai.
:: ==========================================
:REMOVE_OTHER_LANGS
echo.
if "%IS_LIP%"=="0" (
    echo [Buoc 10] Ngon ngu %LANG_CODE% la dang MUI/day du, khong can go cac ngon ngu khac.
    exit /b 0
)
echo [Buoc 10] Dang go cac ngon ngu khac, chi giu tieng Anh en-US va %LANG_CODE%...
echo [Buoc 10] Truoc khi go, dang dat lai ngon ngu he thong ve tieng Anh de go goi Thai...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-SystemPreferredUILanguage -Language en-US" >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "InstallLanguage" /t REG_SZ /d "0409" /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "Default" /t REG_SZ /d "0409" /f >nul 2>&1
if not exist "C:\ProgramData\Savio" mkdir "C:\ProgramData\Savio" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$keep = @('en-US', '%LANG_CODE%'); $pkgs = Get-WindowsPackage -Online; foreach ($p in $pkgs) { if ($p.PackageName -match 'LanguagePack') { $m = [regex]::Match($p.PackageName, '~([a-z]{2}-[A-Z]{2})~'); if ($m.Success) { $tag = $m.Groups[1].Value; if ($keep -notcontains $tag) { Write-Host ('Dang go goi ngon ngu: ' + $tag); Remove-WindowsPackage -Online -PackageName $p.PackageName -NoRestart -ErrorAction SilentlyContinue } } } }" || echo [CANH BAO] Lenh go goi ngon ngu gap loi, van tiep tuc ap dung ngon ngu.
echo Da go xong cac goi ngon ngu khac.
echo [Buoc 10] Dang ap dung lai ngon ngu %LANG_CODE% sau khi go...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-SystemPreferredUILanguage -Language %LANG_CODE%" >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "InstallLanguage" /t REG_SZ /d "%HEX_ID%" /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v "Default" /t REG_SZ /d "%HEX_ID%" /f >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-WinUILanguageOverride -Language %LANG_CODE%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$L = Get-WinUserLanguageList; $N = New-WinUserLanguageList -Language %LANG_CODE%; foreach ($x in $L) { if ($x.LanguageTag -ne '%LANG_CODE%') { $N.Add($x) } }; Set-WinUserLanguageList -LanguageList $N -Force" >nul 2>&1
echo [Buoc 10] Danh sach ngon ngu con lai sau khi go:
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-InstalledLanguage | ForEach-Object { Write-Host $_.LanguageId }"
exit /b 0