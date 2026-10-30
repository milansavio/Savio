<#
act-win.ps1 - Windows 10/11 Home -> Pro, legitimate edition upgrade.
This script only activates Windows with a product key the user owns
and types in at runtime. The key is never written to this file, never
pushed to GitHub, and is stored only locally, encrypted, until phase 2
finishes. No bypass, no KMS server, no other activation method is used.
If the supplied key does not activate, the script stops and shows the
error instead of trying anything else.
Menu at the start, interface is white background with black text:
  1 Kich hoat bang Key co san - the original flow below.
  2 Up Windows Pro khong kich hoat - upgrade only, no key prompt,
    no activation. A cleanup task runs once at logon after the reboot,
    then deletes the ActWin tasks and ActWin temp files and reports
    that the machine is now Pro but not activated.
Fix 2026-10-30: changepk is fire-and-forget. Its exit code must NOT be
treated as upgrade failure, and no forced reboot is issued while
"Preparing for upgrade" runs. The logon task and key file are kept
until Windows reboots itself after preparation.
Fix 2026-10-30: phase 2 DPAPI read. The encrypted key file is written
with NoNewline and Ascii, and phase 2 reads it with Trim plus a BOM
trim and an empty check, because a trailing newline caused
"Input string was not in a correct format" on some machines.
Choice 1 flow: key prompt -> if already Pro, activate now -> otherwise
create a logon task for phase 2, upgrade the edition with Microsoft's
public generic Pro upgrade key, Windows reboots itself, phase 2 installs the user's key
and checks for 30 seconds that the system is Licensed and that the last
5 characters match the key entered. On a match it removes the task and
the local files and shows success. On a mismatch it removes the task
and the key file and shows the error.
Run as Administrator. Delivery: irm <raw url> | iex
#>
$ErrorActionPreference = 'Stop'
try {
    $Host.UI.RawUI.BackgroundColor = 'White'
    $Host.UI.RawUI.ForegroundColor = 'Black'
    Clear-Host
} catch { }
$TaskName = 'ActWin-Phase2'
$CleanupTaskName = 'ActWin-Cleanup'
$WorkDir  = Join-Path $env:ProgramData 'ActWin'
$KeyFile  = Join-Path $WorkDir 'key.txt'
$Phase2File = Join-Path $WorkDir 'act-win-phase2.ps1'
$CleanupFile = Join-Path $WorkDir 'act-win-cleanup.ps1'
$GenericProKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
$RawUrl = 'https://raw.githubusercontent.com/milansavio/Savio/main/act-win.ps1'

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Show-Info($Text, $Title = 'ActWin') {
    try { [System.Windows.Forms.MessageBox]::Show($Text, $Title) | Out-Null }
    catch { Write-Host $Text }
}
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-ProKey {
    while ($true) {
        $input = $null
        try { $input = [Microsoft.VisualBasic.Interaction]::InputBox('Nhap key Windows Pro cua ban (5 nhom x 5 ky tu):', 'ActWin - Nhap key Pro', '') }
        catch { $input = Read-Host 'Nhap key Windows Pro (5 nhom x 5 ky tu)' }
        if ([string]::IsNullOrWhiteSpace($input)) { return $null }
        $key = $input.Trim().ToUpper() -replace '\s+', ''
        if ($key -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') { return $key }
        Show-Info 'Key chua dung dinh dang 5 nhom x 5 ky tu. Vi du: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX' 'ActWin - Key chua hop le'
    }
}
function Get-MenuChoice {
    Write-Host ''
    Write-Host 'ActWin - Chon 1 trong 2:'
    Write-Host '  1. Kích hoạt bằng Key có sẵn'
    Write-Host '  2. Up Windows Pro không kích hoạt'
    Write-Host ''
    while ($true) {
        $choice = (Read-Host 'Nhap 1 hoac 2').Trim()
        if ($choice -eq '1' -or $choice -eq '2') { return $choice }
        Write-Host 'Chi nhap 1 hoac 2.'
    }
}
function Test-Activated($Last5) {
    try {
        $prods = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
            Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
        foreach ($prod in $prods) { if ($prod.PartialProductKey -eq $Last5) { return $true } }
    } catch { }
    return $false
}
function Invoke-Slmgr($Arguments) {
    $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    return (& cscript.exe //Nologo $slmgr @Arguments 2>&1 | Out-String)
}

function Invoke-ActivateAndCheck($Key, $Last5) {
    $out1 = Invoke-Slmgr @('/ipk', $Key)
    $out2 = Invoke-Slmgr @('/ato')
    $deadline = (Get-Date).AddSeconds(30)
    $triedAgain = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Activated $Last5) { return @{ Ok = $true; Output = $out2 } }
        Start-Sleep -Seconds 5
        if (-not $triedAgain) { $out2 = Invoke-Slmgr @('/ato'); $triedAgain = $true }
    }
    if (Test-Activated $Last5) { return @{ Ok = $true; Output = $out2 } }
    return @{ Ok = $false; Output = ($out1 + "`n" + $out2) }
}
function Remove-Phase2Artifacts {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { if (Test-Path $KeyFile) { Remove-Item $KeyFile -Force -ErrorAction SilentlyContinue } } catch { }
}

$Phase2Template = @'
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$TaskName = '__TASK__'
$KeyFile = '__KEYFILE__'
$Phase2File = '__PHASE2FILE__'
$WorkDir = '__WORKDIR__'
function Show-Info2($Text, $Title = 'ActWin') {
    try { [System.Windows.Forms.MessageBox]::Show($Text, $Title) | Out-Null }
    catch { Write-Host $Text }
}
try {
    if (-not (Test-Path $KeyFile)) { throw 'Khong tim thay file key da ma hoa. Hay chay lai act-win.ps1 va nhap key.' }
    $enc = (Get-Content $KeyFile -Raw).Trim()
    $enc = $enc.Trim([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($enc)) { throw 'File key da ma hoa rong. Hay chay lai act-win.ps1 va nhap key.' }
    $secure = ConvertTo-SecureString $enc
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $last5 = $key.Substring($key.Length - 5)
    $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    $o1 = (& cscript.exe //Nologo $slmgr /ipk $key 2>&1 | Out-String)
    $o2 = (& cscript.exe //Nologo $slmgr /ato 2>&1 | Out-String)
    $ok = $false
    $deadline = (Get-Date).AddSeconds(30)
    $again = $false
    while ((Get-Date) -lt $deadline) {
        $prods = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction SilentlyContinue |
            Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
        foreach ($p in $prods) { if ($p.PartialProductKey -eq $last5) { $ok = $true; break } }
        if ($ok) { break }
        Start-Sleep -Seconds 5
        if (-not $again) { $o2 = (& cscript.exe //Nologo $slmgr /ato 2>&1 | Out-String); $again = $true }
    }
    if ($ok) {
        Show-Info2 "Da kich hoat thanh cong Windows Pro. 5 ky tu cuoi trung voi key ban da nhap: $last5" 'ActWin - Thanh cong'
    } else {
        Show-Info2 "Chua kich hoat duoc bang key ban da nhap. Loi tu he thong:`n$o1`n$o2`nHay kiem tra lai key roi chay lai act-win.ps1." 'ActWin - Chua kich hoat'
    }
} catch {
    Show-Info2 "Phase 2 gap loi: $($_.Exception.Message)" 'ActWin - Loi'
} finally {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { if (Test-Path $KeyFile) { Remove-Item $KeyFile -Force -ErrorAction SilentlyContinue } } catch { }
    try { if (Test-Path $Phase2File) { Remove-Item $Phase2File -Force -ErrorAction SilentlyContinue } } catch { }
    try { if ((Test-Path $WorkDir) -and -not (Get-ChildItem $WorkDir -ErrorAction SilentlyContinue)) { Remove-Item $WorkDir -Force -ErrorAction SilentlyContinue } } catch { }
}
'@

$CleanupTemplate = @'
$ErrorActionPreference = 'Stop'
try {
    $Host.UI.RawUI.BackgroundColor = 'White'
    $Host.UI.RawUI.ForegroundColor = 'Black'
} catch { }
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$CTask = '__CTASK__'
$CFile = '__CFILE__'
$CWorkDir = '__CWORKDIR__'
function Show-InfoC($Text, $Title = 'ActWin') {
    try { [System.Windows.Forms.MessageBox]::Show($Text, $Title) | Out-Null }
    catch { Write-Host $Text }
}
try {
    $editionC = ''
    try { $editionC = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID } catch { }
    if ($editionC -match 'Professional') {
        Show-InfoC 'Da upgrade len Windows Pro. Lua chon 2 khong kich hoat, ban co the kich hoat sau bang key cua ban.' 'ActWin - Da len Pro'
    } else {
        Show-InfoC 'May chua len Pro. Hay chay lai act-win.ps1 va chon lai.' 'ActWin - Chua len Pro'
    }
} catch {
    Show-InfoC "Don dep gap loi: $($_.Exception.Message)" 'ActWin - Loi'
} finally {
    try { Unregister-ScheduledTask -TaskName $CTask -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { Unregister-ScheduledTask -TaskName 'ActWin-Phase2' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { Get-ChildItem $env:TEMP -Filter 'ActWin*' -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch { }
    try { if (Test-Path $CWorkDir) { Get-ChildItem $CWorkDir -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
    try { if (Test-Path $CFile) { Remove-Item $CFile -Force -ErrorAction SilentlyContinue } } catch { }
    try { if ((Test-Path $CWorkDir) -and -not (Get-ChildItem $CWorkDir -ErrorAction SilentlyContinue)) { Remove-Item $CWorkDir -Force -ErrorAction SilentlyContinue } } catch { }
}
'@

# Main flow
if (-not (Test-IsAdmin)) {
    $cmd = "irm '$RawUrl' | iex"
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
    exit
}

$edition = ''
try { $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID } catch { }
$isPro = ($edition -match 'Professional')

$menuChoice = Get-MenuChoice

if ($menuChoice -eq '2') {
    if ($isPro) {
        Show-Info 'May da la Windows Pro. Lua chon 2 chi upgrade, khong can lam gi them va khong kich hoat.' 'ActWin - Da la Pro'
        exit
    }
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $cleanup = $CleanupTemplate.Replace('__CTASK__', $CleanupTaskName).Replace('__CFILE__', $CleanupFile).Replace('__CWORKDIR__', $WorkDir)
    Set-Content $CleanupFile $cleanup -Force -Encoding UTF8
    $currentUser2 = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy RemoteSigned -File `"$CleanupFile`""
    $trigger2 = New-ScheduledTaskTrigger -AtLogOn -User $currentUser2
    $principal2 = New-ScheduledTaskPrincipal -UserId $currentUser2 -LogonType Interactive -RunLevel Highest
    $settings2 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $CleanupTaskName -Action $action2 -Trigger $trigger2 -Principal $principal2 -Settings $settings2 -Force | Out-Null
    # changepk launches the edition upgrade and returns while Windows is
    # still showing "Preparing for upgrade". Its exit code is therefore
    # NOT a failure signal here: do not delete the cleanup task on a
    # non-zero code, and do not force a reboot while preparation runs.
    # Windows reboots itself when preparation finishes; the cleanup task
    # stays registered and runs at logon after that reboot. If no
    # Preparing screen appears at all, check the edition and run again.
    & changepk.exe /ProductKey $GenericProKey
    Show-Info 'Dang chuan bi upgrade len Pro, khong kich hoat theo lua chon 2. Dung tat may. May se tu khoi dong lai khi chuan bi xong, sau khi dang nhap lai task don dep se tu xoa task cua ActWin va file tam cua ActWin. Neu khong thay man hinh Preparing va may khong tu khoi dong lai, hay khoi dong lai thu cong - task don dep van con va se chay luc dang nhap.' 'ActWin - Dang chuan bi upgrade'
    exit
}

$key = Get-ProKey
if (-not $key) { Write-Host 'Da huy: khong co key.'; exit }
$last5 = $key.Substring($key.Length - 5)

if ($isPro) {
    $result = Invoke-ActivateAndCheck $key $last5
    if ($result.Ok) {
        Show-Info "Da kich hoat thanh cong Windows Pro. 5 ky tu cuoi trung voi key ban da nhap: $last5" 'ActWin - Thanh cong'
    } else {
        Show-Info "Chua kich hoat duoc bang key ban da nhap. Loi tu he thong:`n$($result.Output)`nHay kiem tra lai key roi chay lai." 'ActWin - Chua kich hoat'
    }
    exit
}

# Not Pro yet: save phase 2 first, then upgrade the edition, then reboot.
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
$secureKey = ConvertTo-SecureString $key -AsPlainText -Force
$encKey = $secureKey | ConvertFrom-SecureString
Set-Content $KeyFile $encKey -Force -NoNewline -Encoding Ascii

$phase2 = $Phase2Template.Replace('__TASK__', $TaskName).Replace('__KEYFILE__', $KeyFile).Replace('__PHASE2FILE__', $Phase2File).Replace('__WORKDIR__', $WorkDir)
Set-Content $Phase2File $phase2 -Force -Encoding UTF8

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy RemoteSigned -File `"$Phase2File`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# changepk launches the edition upgrade and returns while Windows is
# still showing "Preparing for upgrade". Its exit code is therefore
# NOT a failure signal here: do not delete the phase 2 task or the
# encrypted key file on a non-zero code, and do not force a reboot
# while preparation runs. Windows reboots itself when preparation
# finishes; phase 2 stays registered and runs at logon after that
# reboot. If no Preparing screen appears at all, check the edition
# and run again.
& changepk.exe /ProductKey $GenericProKey
Show-Info 'Dang chuan bi upgrade len Pro. Dung tat may. May se tu khoi dong lai khi chuan bi xong, sau khi dang nhap lai phase 2 se tu nhap key cua ban va kiem tra kich hoat. Neu khong thay man hinh Preparing va may khong tu khoi dong lai, hay khoi dong lai thu cong - task phase 2 van con va se chay luc dang nhap.' 'ActWin - Dang chuan bi upgrade'
