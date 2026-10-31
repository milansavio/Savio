# off-smb.ps1 - SMB client fix for Windows 11 24H2, PowerShell version of smb_24h2.bat
# Renamed from smb_24h2.ps1. Run as Administrator (the script self-elevates if it is not):
#   irm https://raw.githubusercontent.com/milansavio/Savio/main/off-smb.ps1 | iex
#
# Core steps, in the same order and with the same values as the .bat:
#   1. Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters
#      RequireSecuritySignature = 1
#   2. Set-SmbClientConfiguration -RequireSecuritySignature $false -Force
#   3. Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force
#
# Differences from the .bat, on purpose (see the comparison at the end of the
# script comments and in the delivery notes):
#   - Console is set to black text on a white background at the start.
#   - If not run as Administrator, the script re-launches itself as Administrator
#     via UAC instead of failing with access denied, which is what the .bat does.
#   - Each step runs independently and the script continues to the next step
#     even if one step fails, exactly like the .bat (three separate lines).
#   - Step 1 adds -Type DWord -Force. On a normal machine the registry value
#     already exists as a DWord, so the result is identical to the .bat. If the
#     value did not exist, the .bat without -Type would create it as a string,
#     while this script creates the correct DWord.
#   - Final verification reads are read-only and change nothing.
#   - The ending pause waits for any key (like the .bat pause) when a console
#     is available, and falls back to Enter otherwise, then exits PowerShell
#     entirely, instead of returning to the prompt.
#
# NOTE on steps 1 and 2: they point in opposite directions for SMB signing.
# Step 1 writes 1, step 2 then sets the client to $false, so the final value
# is $false (no signing required). This script keeps the .bat order exactly.
# Security note: guest logons and no signing weaken SMB security. Only use
# this on a trusted LAN, for a NAS or old device that does not support
# authenticated, signed SMB.

try {
    $Host.UI.RawUI.BackgroundColor = [ConsoleColor]::White
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::Black
    Clear-Host
} catch { }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'off-smb: dang xin quyen Administrator, vui long bam Yes o bang UAC...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'irm https://raw.githubusercontent.com/milansavio/Savio/main/off-smb.ps1 | iex'
    exit
}

try {
    Write-Host 'Buoc 1: Dat RequireSecuritySignature = 1 cho LanmanWorkstation...'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'RequireSecuritySignature' -Value 1 -Type DWord -Force -ErrorAction Stop
    Write-Host 'Buoc 1 xong.'
} catch {
    Write-Host "Buoc 1 loi (van chay tiep buoc sau, giong bat): $($_.Exception.Message)"
}

try {
    Write-Host 'Buoc 2: Set-SmbClientConfiguration -RequireSecuritySignature $false...'
    Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
    Write-Host 'Buoc 2 xong.'
} catch {
    Write-Host "Buoc 2 loi (van chay tiep buoc sau, giong bat): $($_.Exception.Message)"
}

try {
    Write-Host 'Buoc 3: Set-SmbClientConfiguration -EnableInsecureGuestLogons $true...'
    Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force -ErrorAction Stop
    Write-Host 'Buoc 3 xong.'
} catch {
    Write-Host "Buoc 3 loi: $($_.Exception.Message)"
}

# Buoc toi uu bo sung tu snippet OPTIMIZE_SMB, chi lay phan khong xung dot:
#   - MaxCmds = 65535 va MaxThreads = 1000 cho LanmanWorkstation: tang so
#     lenh / luong dong thoi, giup chuyen nhieu file, file lon tren LAN nhanh
#     va do nghe hon, chu khong phai de mo khoa truy cap.
#   - SMB2 = 1 cho LanmanServer: dam bao may nay chia se file ra LAN bang
#     SMB2 hien dai (mac dinh von da bat).
#   - Khoi dong lai LanmanWorkstation dung thu tu: dung dich vu, ghi cac
#     gia tri LanmanWorkstation, roi moi khoi dong lai, de cac gia tri moi
#     co hieu luc ngay, thay vi ghi sau khi da khoi dong nhu snippet goc.
# KHONG bo sung 2 cai sau, vi chung nguoc voi muc dich cua off-smb:
#   - AllowInsecureGuestAuth = 0: tat guest logon, se pha vo buoc 3 vua bat
#     guest o tren, lam NAS khach khong vao duoc nua.
#   - SMB1 = 0: tat SMB1, tot cho bao mat va von la mac dinh tren 24H2,
#     nhung se pha vo thiet bi cu chi noi duoc SMB1, nen khong ep buoc.
Write-Host 'Buoc toi uu: dung LanmanWorkstation de ghi MaxCmds / MaxThreads...'
try {
    Stop-Service -Name 'LanmanWorkstation' -Force -ErrorAction Stop
    Write-Host '  Da dung LanmanWorkstation.'
} catch {
    Write-Host "  Khong dung duoc LanmanWorkstation (co the dang co ket noi SMB mo): $($_.Exception.Message)"
}
try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'MaxCmds' -Value 65535 -Type DWord -Force -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'MaxThreads' -Value 1000 -Type DWord -Force -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB2' -Value 1 -Type DWord -Force -ErrorAction Stop
    Write-Host '  Da ghi MaxCmds = 65535, MaxThreads = 1000, SMB2 = 1.'
} catch {
    Write-Host "  Ghi gia tri toi uu loi: $($_.Exception.Message)"
}
try {
    Start-Service -Name 'LanmanWorkstation' -ErrorAction Stop
    Write-Host '  Da khoi dong lai LanmanWorkstation.'
} catch {
    Write-Host "  Khong khoi dong lai duoc LanmanWorkstation: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Kiem tra lai gia tri hien tai (chi doc, khong thay doi gi):'
try {
    $regValue = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'RequireSecuritySignature' -ErrorAction Stop).RequireSecuritySignature
    Write-Host "  Registry LanmanWorkstation RequireSecuritySignature = $regValue"
} catch {
    Write-Host "  Khong doc duoc registry LanmanWorkstation: $($_.Exception.Message)"
}
try {
    $cfg = Get-SmbClientConfiguration -ErrorAction Stop
    Write-Host "  SmbClient RequireSecuritySignature = $($cfg.RequireSecuritySignature)"
    Write-Host "  SmbClient EnableInsecureGuestLogons = $($cfg.EnableInsecureGuestLogons)"
} catch {
    Write-Host "  Khong doc duoc SmbClientConfiguration: $($_.Exception.Message)"
}
try {
    $ws = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -ErrorAction Stop
    Write-Host "  LanmanWorkstation MaxCmds = $($ws.MaxCmds), MaxThreads = $($ws.MaxThreads)"
    $srv = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -ErrorAction Stop
    Write-Host "  LanmanServer SMB2 = $($srv.SMB2)"
} catch {
    Write-Host "  Khong doc duoc gia tri toi uu: $($_.Exception.Message)"
}
Write-Host ''
Write-Host 'Xong. Hay thu ket noi lai thu muc SMB. Neu van khong duoc, khoi dong lai may roi thu lai.'

try {
    Write-Host 'Nhan phim bat ky de thoat va dong PowerShell...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} catch {
    Read-Host 'Nhan Enter de thoat va dong PowerShell'
}
# Plain exit does not always close the host when the script runs via irm | iex,
# because iex runs the script in the current session scope. Environment.Exit
# terminates the PowerShell process itself, so the window really closes.
[Environment]::Exit(0)
