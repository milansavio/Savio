<#
.SYNOPSIS
    Standalone CLI helper to download, convert (ESD -> CAB), and install a language package
    for Windows 10/11 via Microsoft Store (winget) or UUPDump.

.DESCRIPTION
    Updated pure PowerShell helper (backwards-compatible CLI for Change-Language-4-Win-HomeSL):
    - Fixes 32-bit/64-bit OS architecture detection.
    - Adds HTTP 429 retry/backoff + multi-candidate UUPDump lookup (&lang= with fallback).
    - Uses multi-connection HTTP range downloader for faster download speeds.
    - Automatically converts Windows 11 .ESD language packs to .CAB (native DISM + msdelta/cabinet + makecab)
      and installs via DISM/Add-WindowsPackage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Language,
    [ValidateSet('Full', 'Display', 'Keyboard')]
    [string]$Mode = 'Display',
    [switch]$KeepCab
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$localMain = Join-Path $PSScriptRoot 'Change-Language-4-Win-HomeSL.ps1'
if (Test-Path -LiteralPath $localMain) {
    & $localMain -Language $Language -Mode $Mode -NoGui -KeepCab:$KeepCab
    exit $LASTEXITCODE
}

Write-Host "Khong tim thay Change-Language-4-Win-HomeSL.ps1 cuc bo, dang tai phien ban moi nhat tu GitHub..."
$tmp = Join-Path $env:TEMP ("SavioChangeLang_" + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/milansavio/Savio/main/Change-Language-4-Win-HomeSL.ps1' -OutFile $tmp -UseBasicParsing
    & $tmp -Language $Language -Mode $Mode -NoGui -KeepCab:$KeepCab
    exit $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
