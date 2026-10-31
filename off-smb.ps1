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
#     is available, and falls back to Enter otherwise.
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
Write-Host ''
Write-Host 'Xong. Hay thu ket noi lai thu muc SMB. Neu van khong duoc, khoi dong lai may roi thu lai.'

try {
    Write-Host 'Nhan phim bat ky de thoat...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} catch {
    Read-Host 'Nhan Enter de thoat'
}
