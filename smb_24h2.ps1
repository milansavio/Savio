# smb_24h2.ps1 - SMB client fix for Windows 11 24H2, PowerShell version of smb_24h2.bat
# Run as Administrator (the script self-elevates if it is not):
#   irm https://raw.githubusercontent.com/milansavio/Savio/main/smb_24h2.ps1 | iex
#
# What it does, in the same order as the .bat:
#   1. Sets HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters
#      RequireSecuritySignature = 1
#   2. Set-SmbClientConfiguration -RequireSecuritySignature $false
#   3. Set-SmbClientConfiguration -EnableInsecureGuestLogons $true
#
# NOTE on steps 1 and 2: they point in opposite directions for SMB signing.
# Step 1 writes 1 to the workstation registry value, step 2 then sets the
# SMB client configuration to $false, so the value that wins at the end is
# $false (no signing required). This script keeps the .bat order exactly,
# so its result is identical to the .bat, and the verification at the end
# prints the final values so you can see that. If you actually want signing
# required, remove step 2 instead of running this script as-is.
#
# Security note: EnableInsecureGuestLogons and turning off RequireSecuritySignature
# weaken SMB security (guest logons send no credentials, unsigned traffic can be
# tampered with on the network). Only use this on a trusted LAN, for a NAS or
# old device that does not support authenticated, signed SMB, not on a public
# or untrusted network.

$ErrorActionPreference = 'Stop'

# Self-elevate: re-run the same irm | iex command as Administrator, then exit.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'smb_24h2: dang xin quyen Administrator, vui long bam Yes o bang UAC...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'irm https://raw.githubusercontent.com/milansavio/Savio/main/smb_24h2.ps1 | iex'
    exit
}

try {
    Write-Host 'Buoc 1: Dat RequireSecuritySignature = 1 cho LanmanWorkstation...'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'RequireSecuritySignature' -Value 1 -Type DWord -Force
    Write-Host 'Buoc 1 xong.'

    Write-Host 'Buoc 2: Set-SmbClientConfiguration -RequireSecuritySignature $false...'
    Set-SmbClientConfiguration -RequireSecuritySignature $false -Force
    Write-Host 'Buoc 2 xong.'

    Write-Host 'Buoc 3: Set-SmbClientConfiguration -EnableInsecureGuestLogons $true...'
    Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force
    Write-Host 'Buoc 3 xong.'

    Write-Host ''
    Write-Host 'Kiem tra lai gia tri hien tai:'
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
} catch {
    Write-Host "smb_24h2 gap loi: $($_.Exception.Message)"
    throw
}

Read-Host 'Nhan Enter de thoat'
