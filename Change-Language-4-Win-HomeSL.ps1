<#
.SYNOPSIS
    Change-Language-4-Win-HomeSL.ps1 - Pure PowerShell GUI & CLI tool to install and switch
    display languages and keyboards on Windows 10/11 (including Home Single Language & OEM multi-language laptops).

.DESCRIPTION
    100% pure PowerShell implementation (zero .bat / .vbs dependencies):
    - Self-elevates cleanly via UAC (supports both local execution and 'irm ... | iex').
    - Modern responsive WinForms GUI (non-blocking background Runspace + live progress & logs) plus -NoGui CLI support.
    - Multi-tier fast installation: Windows Update (Add-WindowsCapability / Install-Language) -> Microsoft Store (winget)
      -> UUPDump API (429 retry/backoff + multi-connection range downloader).
    - Automated Windows 11 ESD -> CAB conversion using native DISM, built-in msdelta.dll/cabinet.dll (DCM/DCN/DCS),
      and makecab.exe with zero external tools required.
    - ASUS/MSI multi-OEM language conflict fix: validates/installs en-US base MUI before safely removing conflicting
      OEM language packs (e.g. th-TH, zh-CN), keeps InstallLanguage on base MUI (0409) for LIP languages (vi-VN),
      syncs Welcome Screen/system accounts, clears Settings cache across user profiles, and manages Savio-LangLock.

.EXAMPLE
    irm https://raw.githubusercontent.com/milansavio/Savio/main/Change-Language-4-Win-HomeSL.ps1 | iex
    .\Change-Language-4-Win-HomeSL.ps1 -Language vi-VN -Mode Full -NoGui
#>
[CmdletBinding()]
param(
    [string]$Language,
    [ValidateSet('Full', 'Display', 'Keyboard')]
    [string]$Mode = 'Full',
    [switch]$NoGui,
    [switch]$SkipOemCleanup,
    [switch]$SkipLangLock,
    [switch]$KeepCab,
    [switch]$DisableWuUnpause
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:RawUrl = 'https://raw.githubusercontent.com/milansavio/Savio/main/Change-Language-4-Win-HomeSL.ps1'
$script:WorkRoot = Join-Path $env:ProgramData 'Savio'
$script:StagingRoot = Join-Path $script:WorkRoot 'Work'
$script:LogDir = Join-Path $script:WorkRoot 'Logs'
$script:LogFile = Join-Path $script:LogDir 'ChangeLang.log'
$script:PauseBackupFile = Join-Path $script:WorkRoot 'wu_pause_backup.json'
$script:LangLockTaskName = 'Savio-LangLock'
$script:LangLockScript = Join-Path $script:WorkRoot 'LangLock.ps1'

# Ensure TLS 1.2 + TLS 1.3 (where supported)
try {
    $secProto = [Net.SecurityProtocolType]::Tls12
    if ([Enum]::IsDefined([Net.SecurityProtocolType], 'Tls13')) {
        $secProto = $secProto -bor [Net.SecurityProtocolType]::Tls13
    }
    [Net.ServicePointManager]::SecurityProtocol = $secProto
    [Net.ServicePointManager]::DefaultConnectionLimit = 16
    [Net.ServicePointManager]::Expect100Continue = $false
} catch { }

# ==============================================================================
# 1. SELF-ELEVATION (Single Clean UAC Prompt, Local + Remote 'irm | iex')
# ==============================================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host 'Change-Language: Dang yeu cau quyen Administrator (vui long chon Yes tren bang UAC)...'
    $selfPath = $PSCommandPath
    $psExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path $psExe)) { $psExe = 'powershell.exe' }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($selfPath -and (Test-Path -LiteralPath $selfPath)) {
        $argList += @('-File', ('"' + $selfPath + '"'))
        if ($Language) { $argList += @('-Language', ('"' + $Language + '"')) }
        if ($Mode) { $argList += @('-Mode', $Mode) }
        if ($NoGui) { $argList += '-NoGui' }
        if ($SkipOemCleanup) { $argList += '-SkipOemCleanup' }
        if ($SkipLangLock) { $argList += '-SkipLangLock' }
        if ($KeepCab) { $argList += '-KeepCab' }
        if ($DisableWuUnpause) { $argList += '-DisableWuUnpause' }
    } else {
        $cmd = "irm '$script:RawUrl' | iex"
        $argList += @('-Command', ('"' + $cmd + '"'))
    }

    try {
        Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $argList | Out-Null
    } catch {
        Write-Host '[LOI] Can quyen Administrator de chay tool. Hay mo PowerShell bang Run as Administrator roi thu lai.' -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
    exit
}

# ==============================================================================
# 2. LANGUAGE CATALOG & SHARED HELPERS
# ==============================================================================
function T {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [System.Text.RegularExpressions.Regex]::Unescape($Text)
}

function Initialize-SavioFolders {
    foreach ($dir in @($script:WorkRoot, $script:StagingRoot, $script:LogDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

$script:LogWriteLock = New-Object object
function Write-AppLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')]
        [string]$Level = 'INFO',
        [hashtable]$Sync = $null
    )
    $ts = (Get-Date).ToString('HH:mm:ss')
    $fullTs = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    $fileLine = "[$fullTs] [$Level] $Message"

    [System.Threading.Monitor]::Enter($script:LogWriteLock)
    try {
        Initialize-SavioFolders
        [System.IO.File]::AppendAllText($script:LogFile, ($fileLine + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    } catch { } finally {
        [System.Threading.Monitor]::Exit($script:LogWriteLock)
    }

    if ($null -ne $Sync -and $null -ne $Sync.LogQueue) {
        $Sync.LogQueue.Enqueue($line)
    } else {
        switch ($Level) {
            'ERROR' { Write-Host $line -ForegroundColor Red }
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'OK'    { Write-Host $line -ForegroundColor Green }
            default { Write-Host $line }
        }
    }
}

function Set-UiProgress {
    param(
        [hashtable]$Sync,
        [string]$Status = $null,
        [int]$Percent = -1,
        [string]$Style = 'Continuous'
    )
    if ($null -eq $Sync) { return }
    if ($null -ne $Status) { $Sync.StatusText = $Status }
    if ($Percent -ge 0) { $Sync.ProgressPercent = [Math]::Min(100, [Math]::Max(0, $Percent)) }
    if ($Style) { $Sync.ProgressStyle = $Style }
}

$script:LanguageCatalog = @(
    @{ Tag = 'vi-VN'; NameAscii = 'Tieng Viet'; NameUi = 'Ti\u1ebfng Vi\u1ec7t (Vi\u1ec7t Nam)'; HexId = '042a'; StoreId = '9P0W68X0XZPT'; IsLip = $true;  BaseMui = 'en-US' }
    @{ Tag = 'en-US'; NameAscii = 'Tieng Anh - My'; NameUi = 'Ti\u1ebfng Anh - M\u1ef9 (English US)'; HexId = '0409'; StoreId = '9PDSCC711RVF'; IsLip = $false; BaseMui = 'en-US' }
    @{ Tag = 'en-GB'; NameAscii = 'Tieng Anh - Anh'; NameUi = 'Ti\u1ebfng Anh - Anh (English UK)'; HexId = '0809'; StoreId = '9NT52VQ39BVN'; IsLip = $false; BaseMui = 'en-GB' }
    @{ Tag = 'ja-JP'; NameAscii = 'Tieng Nhat Ban'; NameUi = 'Ti\u1ebfng Nh\u1eadt B\u1ea3n (Japanese)'; HexId = '0411'; StoreId = '9N1W692FV4S1'; IsLip = $false; BaseMui = 'ja-JP' }
    @{ Tag = 'ko-KR'; NameAscii = 'Tieng Han Quoc'; NameUi = 'Ti\u1ebfng H\u00e0n Qu\u1ed1c (Korean)'; HexId = '0412'; StoreId = '9N4TXPCVRNGF'; IsLip = $false; BaseMui = 'ko-KR' }
    @{ Tag = 'zh-CN'; NameAscii = 'Tieng Trung - Gian'; NameUi = 'Ti\u1ebfng Trung - Gi\u1ea3n th\u1ec3 (Simplified)'; HexId = '0804'; StoreId = '9NRMNT6GMZ70'; IsLip = $false; BaseMui = 'zh-CN' }
    @{ Tag = 'zh-TW'; NameAscii = 'Tieng Trung - Phon'; NameUi = 'Ti\u1ebfng Trung - Ph\u1ed3n th\u1ec3 (Traditional)'; HexId = '0404'; StoreId = '9PCJ4DHCQ1JQ'; IsLip = $false; BaseMui = 'zh-TW' }
    @{ Tag = 'th-TH'; NameAscii = 'Tieng Thai Lan'; NameUi = 'Ti\u1ebfng Th\u00e1i Lan (Thai)'; HexId = '041e'; StoreId = '9MSTWFRL0LR4'; IsLip = $false; BaseMui = 'th-TH' }
    @{ Tag = 'fr-FR'; NameAscii = 'Tieng Phap'; NameUi = 'Ti\u1ebfng Ph\u00e1p (French)'; HexId = '040c'; StoreId = '9NHMG4BJKMDG'; IsLip = $false; BaseMui = 'fr-FR' }
    @{ Tag = 'de-DE'; NameAscii = 'Tieng Duc'; NameUi = 'Ti\u1ebfng \u0110\u1ee9c (German)'; HexId = '0407'; StoreId = '9P6CT0SLW589'; IsLip = $false; BaseMui = 'de-DE' }
    @{ Tag = 'ru-RU'; NameAscii = 'Tieng Nga'; NameUi = 'Ti\u1ebfng Nga (Russian)'; HexId = '0419'; StoreId = '9NMJCX77QKPX'; IsLip = $false; BaseMui = 'ru-RU' }
    @{ Tag = 'es-ES'; NameAscii = 'Tieng Tay Ban Nha'; NameUi = 'Ti\u1ebfng T\u00e2y Ban Nha (Spanish)'; HexId = '0c0a'; StoreId = '9NWVGWLHPB1Z'; IsLip = $false; BaseMui = 'es-ES' }
    @{ Tag = 'pt-BR'; NameAscii = 'Tieng Bo Dao Nha'; NameUi = 'Ti\u1ebfng B\u1ed3 \u0110\u00e0o Nha (Brazil)'; HexId = '0416'; StoreId = '9P8LBDM4FW35'; IsLip = $false; BaseMui = 'pt-BR' }
    @{ Tag = 'it-IT'; NameAscii = 'Tieng Y'; NameUi = 'Ti\u1ebfng \u00dd (Italian)'; HexId = '0410'; StoreId = '9P8PQWNS6VJX'; IsLip = $false; BaseMui = 'it-IT' }
    @{ Tag = 'id-ID'; NameAscii = 'Tieng Indonesia'; NameUi = 'Ti\u1ebfng Indonesia'; HexId = '0421'; StoreId = '9P4X3N4SDK8P'; IsLip = $true;  BaseMui = 'en-US' }
    @{ Tag = 'hi-IN'; NameAscii = 'Tieng An Do'; NameUi = 'Ti\u1ebfng \u1ea4n \u0110\u1ed9 (Hindi)'; HexId = '0439'; StoreId = '9NZC3GRX8LD3'; IsLip = $true;  BaseMui = 'en-US' }
)

function Resolve-LanguageMeta {
    param([string]$Tag)
    $clean = ($Tag -replace '\s+', '').Trim()
    $hit = $script:LanguageCatalog | Where-Object { $_.Tag -ieq $clean } | Select-Object -First 1
    if ($hit) { return [PSCustomObject]$hit }

    # Dynamic lookup via .NET CultureInfo for custom language tags
    $ci = [System.Globalization.CultureInfo]::GetCultureInfo($clean)
    $hex = $ci.LCID.ToString('x4')
    $fullMuiKnown = @('ar-sa','bg-bg','cs-cz','da-dk','de-de','el-gr','en-gb','en-us','es-es','es-mx','et-ee','fi-fi','fr-ca','fr-fr','he-il','hr-hr','hu-hu','it-it','ja-jp','ko-kr','lt-lt','lv-lv','nb-no','nl-nl','pl-pl','pt-br','pt-pt','ro-ro','ru-ru','sk-sk','sl-si','sr-latn-rs','sv-se','th-th','tr-tr','uk-ua','zh-cn','zh-tw')
    $isLip = ($fullMuiKnown -notcontains $ci.Name.ToLowerInvariant())
    return [PSCustomObject]@{
        Tag       = $ci.Name
        NameAscii = $ci.EnglishName
        NameUi    = "$($ci.NativeName) ($($ci.Name))"
        HexId     = $hex
        StoreId   = $null
        IsLip     = $isLip
        BaseMui   = $(if ($isLip) { 'en-US' } else { $ci.Name })
    }
}

function Get-SystemArchNormalized {
    $raw = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $raw = $env:PROCESSOR_ARCHITEW6432 }
    if ([Environment]::Is64BitOperatingSystem -and ($raw -eq 'x86' -or -not $raw)) {
        return 'amd64'
    }
    switch -Regex ($raw) {
        '^AMD64$' { return 'amd64' }
        '^ARM64$' { return 'arm64' }
        '^x86$'   { return 'x86' }
        default   { return $raw.ToLowerInvariant() }
    }
}

# ==============================================================================
# 3. EMBEDDED NATIVE C# MODULE (Fast Multi-Range Downloader + Native SxS Expand)
# ==============================================================================
$script:WcpSrcManifestGzipB64 = 'H4sIAAAAAAAEAM1a6XMayRX/vlX7P0xNsrWWKzAcEsYIdhcDtigL4zDIR6IUNcw00NEcbHePBEnlf8/ray4GCXn9YcsfxPTx+vfu97rd/XUX+MY9IhRHYc+sV2umgUI38nC47pk387eVtmlQ5oSe40ch6pl7RM1ff/nxh65DKQqW/t4AAiHtmTEJO9TdoMChlQC7JKLRilXcKOg4NKjeN00jcEK8QpR9yp3mIeoSvGViZIi2frQPUMhgAtOt7+w/OAHKT7jRdk/wesN65kD/NF64Z8ZEH2sMIrKNiMOJVo2+7xszvogaM0QRuUde1QQWDCNhYuwBZcz2RihOSwhVPuPQix5oxUxl1KqaxpZELqI0In3ibjBDLosJ7Nu1W6bhO+E6dtbwGaKYEcc3jWWMfW++38IYQT5yKAIS8dLH7nu0n0d3CMg268tVs33Rcrxm6xw1L5ITbeCXE4NfO9s0LIncQ1sUAmp3zwXlRrDYWfpinWkQRKOYuEgeOVNfVDKd2cz6WokpOblnSxBBv8eYAnN623F5VdMjTpKTE3it86ykXn6rjCzNknXAk5STlXImB1bYRxq25/vCABkOha18dNimZ/71BYmBuwBV6Z4yFDQbZ+ADgr8PmX04ABNjeouAXw0ZIwid3SaSpsiNCQhqqKw8Iursz7OPi7fj69FiOHrbv7meL+zh8DrDD8VrwATSGoer6GQfSzWV7M+cPJxNrtE98ntmVnC5k/Qo0LtvdDYO3cizO2LgSQSNDAIPCHfmxAnpKiIBVXT4aM/cMLbtWNbDw0P1oVmNyNpq1Go1q/baglV8yV9SQgekwKHXEQh1EzyG5wqwp6dXtcWmnAvjyGMsgB/iNdjGBLFN5D0Xfhbk08vpxmlctHLYMgg+OX6Mni0/xV2GRKLyVLvKSbhTqLiCCXgpIEc0iRZqaH+Sq9yaRvQQItIzGYmzseNRVxiOZ8c8wUrOfxagBxm5i3h0/LSKjHYhaLoOmNLTzqZXVu/rCb0AYg5Evg3eJnJzHYbABvaTZCoVBvaKqaaqUk11ILfhXDCFVMn/lYTE1kX9vLlcNl6hV47bXpoGgxgq45QNSdwHt+b520VvQcf0TRSxAWgBuzwvWc8EVLUhe+KSMP9knM6AkiRyh2tJaagGjZd6rGdezecfc+GAShJDhzkKtFiSrxh++8kWJjkDjn+61eZ56xHMod9yg/1bBfSHCInIIAoZiXyePUngiOAOeUmaVOlWURQRqEA8sI/Qkwz2zDtEQuQPxcJCaZPl4DFvyApGhOeU2UzgKkoscZYjRte1igYK9r7GlJE9qC0x2cyYcYeUJK/ej74uBtd92x7Zi9l0Or8dXNvjYeJXK8enWUfXRGTY0lzd8y9VkIzeLex/qCE+BwWOLNaucMh4/gc1chMpcdynQwlQ54CPRZMMi0oyB4LowoGUZdOhPjBTCbm8sFF2kzfOIrYhWuEQc/boUzaQLs3HxtFgPp0VeaKeBxY77diVeuWi0q5VXl+0arV2u31RaZ7X2xeNRuv8daXebtZrzXbt/Bx+XjQbrxutZr3SaLyqn79qn7fO3/3B/cPOxxf9y8H48l3/8vLyj9E6A0qXtV29WYMAwql95SPj6WA81fS/Fte86RfXyBH5PXv3hY/c8JHpeDAeT+WawbS4hiOvX1QalfrZcYO0vkmBJXXen0l3l2+/k+a0tPvZL6WxnCZKZG53XvRvAIndB+VCLTOs1estWPJ5+N3VURog/kwK+X7OxCnNEiXoL+0g6usmt/K5bsAz1CkRD6rOkpCZ7lbBOB96u34EhQr+jwCRJinVbBpu7MuGEoWVGztbazICtc+cd8S52CyGDezxvJ3k5iQRlTZ+1jECabGRyWTZ5uIQBM81Crti94A/3purm47Tb1ZUDbpCoo979j4MRQSJ+ZE5OUOrGDKqqamWQxGsJgSrQNCCYpt3IOdWrW3JbRllbEl0jz1EjHXMBfff/5lGAIYABRYvSWWNUVqsmUnxoMWWbgCP3QdLXrLlSsNo60YeKuRZOagP5XqWqqnysnEx/TiYDkcQFQaj8Sf+9+83I3tenYpNE7nnzMwUmkd2pIgeXaRMpV4vutEh9C5z6F2BFz50jJN5336f4J/DwlL02VUFzPkpjbQItIiq626cEMreAlI1argbrnWzBPRZquBEmaqQnurIk29TRIV7eFoXatWHiHgFBGrUAHu965m13ckY8geWEO8GzrZwmJDWxNkqcp/UZ77slztLYFRTVSmx1w7Sm6WPyKErIOmC50BcYkUf0MMGE9ooovJ4L4VDWZ+DN3duxiHLemAUMzm5o5045HdGyBvz21irSIrHEpcZbhTznJFQKCwrPTPE3AVsIZLyo6maOzjVkscWJKa5zttviYRUsMtvF2OGsjeORFuChDvi0360HvgOpdg1DV9ervE5nsGgk9QWfKhwQVukWM5ywQWEvcJfBTRpn8QP3XjXinZaYKFr6cCbZJ/ciq7QEFB7ToS/sOoNS28EzGJtcqHfqNbK4r6z3frYFcLQ13A9s4p2kDgh+/lLxwV2Xcj7USCujMWud0my0COqG723IU3RdFjaRgx98gQkeSQvKMg2YoWuPPs5HvKBNEth1VyDbAKoNPDWR/31GtpF0Elqnvyv3JlqECqaspuUwh2AAgUQVg7Qt0EY0vGfgugh5mBf3eXK1xnimYaMs4/hksEVYutqoQ5f+A5ZowVxHsTAidBT8H0G9ryMi/GmdImCFkZDWTuVufHjZJP5fEZIlPuY8WurVZVXWdHTDfBaph2DIsbAT+mn1N2Sy4B4y2/+kTeIgm0U5p3ucDIL9cj7yaLspi9feB6QTUicXO2VvbCUPFZp+znydvPylOu+gvRmcIq07MfetKSajgqwbCqJZYEDGENkb5GLV9j9hgcTUP2XwNcbc8GDxD5vNqBxQTtIabJULfgyDl0/9lDRnqPlv0FwWctMprYOA3MMlU/O1CWU+cvV++vJrf3Vno8mt4OYEGBT9UxA5lbfwN6+NP758l9g5pLKgR+VH8zNvogTmhLOX0YFUhSJ2Auy1feJ2lXkN0hnhdex8p6TbTJ9XGqevvzBDZ7IVp8n44EAxHNWw+IZI7mhzEO1xf6U+R31FAZ1GAwceW+pW18m13K/qTk+fDmWV9OMR1nGMxjdQgt9dGFWLwIKhhJAXJsmfgncdx67WebboF+C+OkKXSzB0Xnt5HWgiUdrRA5COZ8LnN2YmwbF96isnc0uxeHB0pJqtYAjZ3F51opMgwZhZvdsrin6PUbpZXhuDgKe6KmBz6nrxoRbZ7iElOAhyJzAkh6tpRGQqarT62zQ7g0OHXBPAYSXhGs0DkCVjL+Vi0A5Q+JJoFwQJdDkRIbXohg05EM4yyiC+B2eAuZQbnIo+1Qih4CM5/PrdihwoNB98bO497+eDvrXi0l/cDX+MDohLP18JqlRGeGhvLuholQUg/FSRX4VU8Zh8myfzwKpG2by9zG37QZQD3m5BxIlO5q5+M8tKpCDMf4qmvzHAfEfFBwS8JeK4efpbHgoC6UDWc6L8lD2LZnmKCPkH3/4PxESuo9qIwAA'

$script:NativeCSharpCode = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace SavioLangNative {
    public static class SxsExpand {
        [StructLayout(LayoutKind.Sequential)]
        private struct DELTA_INPUT {
            public IntPtr lpStart;
            public UIntPtr uSize;
            [MarshalAs(UnmanagedType.Bool)]
            public bool Editable;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DELTA_OUTPUT {
            public IntPtr lpStart;
            public UIntPtr uSize;
        }

        [DllImport("msdelta.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ApplyDeltaB(ulong ApplyFlags, DELTA_INPUT Source, DELTA_INPUT Delta, out DELTA_OUTPUT lpTarget);

        [DllImport("msdelta.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeltaFree(IntPtr lpMemory);

        [DllImport("cabinet.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateDecompressor(uint Algorithm, IntPtr AllocationRoutines, out IntPtr DecompressorHandle);

        [DllImport("cabinet.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Decompress(IntPtr DecompressorHandle, byte[] CompressedData, UIntPtr CompressedDataSize, byte[] UncompressedBuffer, UIntPtr UncompressedBufferSize, out UIntPtr UncompressedDataSize);

        [DllImport("cabinet.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseDecompressor(IntPtr DecompressorHandle);

        private const uint COMPRESS_ALGORITHM_LZMS = 5;
        private const uint COMPRESS_RAW = 1u << 29;

        public static byte[] GunzipBase64(string b64) {
            byte[] gz = Convert.FromBase64String(b64);
            using (var msIn = new MemoryStream(gz))
            using (var gs = new GZipStream(msIn, CompressionMode.Decompress))
            using (var msOut = new MemoryStream()) {
                gs.CopyTo(msOut);
                return msOut.ToArray();
            }
        }

        private static byte[] ApplyMsDelta(byte[] sourceBytes, byte[] deltaBytes, int deltaOffset) {
            int delLen = deltaBytes.Length - deltaOffset;
            if (delLen <= 0) throw new InvalidDataException("Delta buffer is empty");

            IntPtr pSrc = IntPtr.Zero;
            IntPtr pDel = Marshal.AllocHGlobal(delLen);
            try {
                if (sourceBytes != null && sourceBytes.Length > 0) {
                    pSrc = Marshal.AllocHGlobal(sourceBytes.Length);
                    Marshal.Copy(sourceBytes, 0, pSrc, sourceBytes.Length);
                }
                Marshal.Copy(deltaBytes, deltaOffset, pDel, delLen);

                var src = new DELTA_INPUT {
                    lpStart = pSrc,
                    uSize = sourceBytes != null ? (UIntPtr)sourceBytes.Length : UIntPtr.Zero,
                    Editable = false
                };
                var del = new DELTA_INPUT {
                    lpStart = pDel,
                    uSize = (UIntPtr)delLen,
                    Editable = false
                };
                DELTA_OUTPUT outp;
                if (!ApplyDeltaB(0, src, del, out outp)) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                try {
                    int outLen = checked((int)(ulong)outp.uSize);
                    byte[] result = new byte[outLen];
                    Marshal.Copy(outp.lpStart, result, 0, outLen);
                    return result;
                } finally {
                    DeltaFree(outp.lpStart);
                }
            } finally {
                if (pSrc != IntPtr.Zero) Marshal.FreeHGlobal(pSrc);
                Marshal.FreeHGlobal(pDel);
            }
        }

        private static byte[] ExpandDcs(byte[] data) {
            if (data.Length < 12) throw new InvalidDataException("Invalid DCS header");
            uint numBlocks = BitConverter.ToUInt32(data, 4);
            uint totalUncomp = BitConverter.ToUInt32(data, 8);
            if (numBlocks == 0 || totalUncomp == 0) throw new InvalidDataException("Empty DCS stream");

            IntPtr hDecomp;
            if (!CreateDecompressor(COMPRESS_RAW | COMPRESS_ALGORITHM_LZMS, IntPtr.Zero, out hDecomp)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            try {
                byte[] result = new byte[totalUncomp];
                int pos = 12;
                int outPos = 0;
                for (uint i = 0; i < numBlocks; i++) {
                    if (pos + 8 > data.Length) throw new InvalidDataException("Truncated DCS block");
                    uint blkSize = BitConverter.ToUInt32(data, pos);
                    uint uncompSize = BitConverter.ToUInt32(data, pos + 4);
                    if (blkSize < 4 || pos + 4 + blkSize > data.Length) throw new InvalidDataException("Corrupt DCS block size");
                    int compLen = (int)(blkSize - 4);
                    byte[] compSlice = new byte[compLen];
                    Buffer.BlockCopy(data, pos + 8, compSlice, 0, compLen);
                    byte[] uncompSlice = new byte[uncompSize];
                    UIntPtr written;
                    if (!Decompress(hDecomp, compSlice, (UIntPtr)compLen, uncompSlice, (UIntPtr)uncompSize, out written)) {
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    }
                    int w = checked((int)(ulong)written);
                    if (outPos + w > result.Length) throw new InvalidDataException("DCS output overflow");
                    Buffer.BlockCopy(uncompSlice, 0, result, outPos, w);
                    outPos += w;
                    pos += (int)(blkSize + 4);
                }
                return result;
            } finally {
                CloseDecompressor(hDecomp);
            }
        }

        public static int ExpandManifestDirectory(string directoryPath, string wcpBase64Gzip) {
            byte[] wcpSrc = GunzipBase64(wcpBase64Gzip);
            string[] manifests = Directory.GetFiles(directoryPath, "*.manifest", SearchOption.AllDirectories);
            int expandedCount = 0;
            foreach (string path in manifests) {
                byte[] raw = File.ReadAllBytes(path);
                if (raw.Length < 4) continue;
                byte[] output = null;
                // DCM\x01 = 44 43 4D 01
                if (raw[0] == 0x44 && raw[1] == 0x43 && raw[2] == 0x4D && raw[3] == 0x01) {
                    output = ApplyMsDelta(wcpSrc, raw, 4);
                }
                // DCN\x01 = 44 43 4E 01
                else if (raw[0] == 0x44 && raw[1] == 0x43 && raw[2] == 0x4E && raw[3] == 0x01) {
                    output = ApplyMsDelta(null, raw, 4);
                }
                // DCS\x01 = 44 43 53 01
                else if (raw[0] == 0x44 && raw[1] == 0x43 && raw[2] == 0x53 && raw[3] == 0x01) {
                    output = ExpandDcs(raw);
                }

                if (output != null && output.Length > 0) {
                    File.WriteAllBytes(path, output);
                    expandedCount++;
                }
            }
            return expandedCount;
        }
    }

    public static class FastDownloader {
        private static HttpWebRequest CreateRequest(string url, string method) {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Method = method;
            req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) SavioLangTool/2.0";
            req.AllowAutoRedirect = true;
            req.Timeout = 30000;
            req.ReadWriteTimeout = 30000;
            return req;
        }

        public static void DownloadFile(string url, string destPath, int connections, Action<long, long, double> progressCallback, Func<bool> shouldCancel) {
            long totalBytes = -1;
            bool supportsRanges = false;
            string effectiveUrl = url;

            try {
                var headReq = CreateRequest(url, "HEAD");
                using (var resp = (HttpWebResponse)headReq.GetResponse()) {
                    effectiveUrl = resp.ResponseUri.AbsoluteUri;
                    totalBytes = resp.ContentLength;
                    string ar = resp.Headers["Accept-Ranges"];
                    if (!string.IsNullOrEmpty(ar) && ar.IndexOf("bytes", StringComparison.OrdinalIgnoreCase) >= 0) {
                        supportsRanges = true;
                    }
                }
            } catch {
                // Fallback if HEAD is blocked or fails
            }

            string dir = Path.GetDirectoryName(destPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);

            if (supportsRanges && totalBytes >= (2L * 1024L * 1024L) && connections > 1) {
                DownloadMultiPart(effectiveUrl, destPath, totalBytes, Math.Min(connections, 6), progressCallback, shouldCancel);
            } else {
                DownloadSingleStream(effectiveUrl, destPath, totalBytes, progressCallback, shouldCancel);
            }
        }

        private static void DownloadSingleStream(string url, string destPath, long knownTotal, Action<long, long, double> progressCallback, Func<bool> shouldCancel) {
            var req = CreateRequest(url, "GET");
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var inStream = resp.GetResponseStream())
            using (var outStream = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 65536)) {
                long total = resp.ContentLength > 0 ? resp.ContentLength : knownTotal;
                byte[] buf = new byte[65536];
                long downloaded = 0;
                var sw = System.Diagnostics.Stopwatch.StartNew();
                long lastReportMs = 0;
                int read;
                while ((read = inStream.Read(buf, 0, buf.Length)) > 0) {
                    if (shouldCancel != null && shouldCancel()) throw new OperationCanceledException("Download cancelled");
                    outStream.Write(buf, 0, read);
                    downloaded += read;
                    long elapsed = sw.ElapsedMilliseconds;
                    if (progressCallback != null && (elapsed - lastReportMs >= 200 || (total > 0 && downloaded == total))) {
                        double mbps = elapsed > 0 ? (downloaded / 1048576.0) / (elapsed / 1000.0) : 0.0;
                        progressCallback(downloaded, total, mbps);
                        lastReportMs = elapsed;
                    }
                }
                if (progressCallback != null) {
                    double mbps = sw.Elapsed.TotalSeconds > 0 ? (downloaded / 1048576.0) / sw.Elapsed.TotalSeconds : 0.0;
                    progressCallback(downloaded, total > 0 ? total : downloaded, mbps);
                }
            }
        }

        private static void DownloadMultiPart(string url, string destPath, long totalBytes, int parts, Action<long, long, double> progressCallback, Func<bool> shouldCancel) {
            long chunkSize = totalBytes / parts;
            string[] partFiles = new string[parts];
            long downloaded = 0;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            Exception firstErr = null;
            var cts = new CancellationTokenSource();

            var tasks = new Task[parts];
            for (int i = 0; i < parts; i++) {
                int idx = i;
                long start = idx * chunkSize;
                long end = (idx == parts - 1) ? (totalBytes - 1) : ((idx + 1) * chunkSize - 1);
                partFiles[idx] = destPath + ".part" + idx;

                tasks[idx] = Task.Run(() => {
                    try {
                        var req = CreateRequest(url, "GET");
                        req.AddRange(start, end);
                        using (var resp = (HttpWebResponse)req.GetResponse())
                        using (var inStream = resp.GetResponseStream())
                        using (var fs = new FileStream(partFiles[idx], FileMode.Create, FileAccess.Write, FileShare.None, 65536)) {
                            byte[] buf = new byte[65536];
                            int read;
                            while ((read = inStream.Read(buf, 0, buf.Length)) > 0) {
                                if (cts.IsCancellationRequested) {
                                    throw new OperationCanceledException("Download cancelled");
                                }
                                fs.Write(buf, 0, read);
                                Interlocked.Add(ref downloaded, read);
                            }
                        }
                    } catch (Exception ex) {
                        Interlocked.CompareExchange(ref firstErr, ex, null);
                        cts.Cancel();
                    }
                });
            }

            while (!Task.WaitAll(tasks, 200)) {
                if (shouldCancel != null && shouldCancel()) cts.Cancel();
                if (progressCallback != null) {
                    long d = Interlocked.Read(ref downloaded);
                    double mbps = sw.Elapsed.TotalSeconds > 0 ? (d / 1048576.0) / sw.Elapsed.TotalSeconds : 0.0;
                    progressCallback(d, totalBytes, mbps);
                }
            }

            if (firstErr != null) {
                CleanupParts(partFiles);
                throw firstErr;
            }

            if (progressCallback != null) {
                double mbps = sw.Elapsed.TotalSeconds > 0 ? (totalBytes / 1048576.0) / sw.Elapsed.TotalSeconds : 0.0;
                progressCallback(totalBytes, totalBytes, mbps);
            }

            // Merge part files cleanly
            try {
                using (var dest = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 131072)) {
                    byte[] buf = new byte[131072];
                    for (int i = 0; i < parts; i++) {
                        using (var pf = new FileStream(partFiles[i], FileMode.Open, FileAccess.Read, FileShare.Read, 131072)) {
                            int r;
                            while ((r = pf.Read(buf, 0, buf.Length)) > 0) {
                                dest.Write(buf, 0, r);
                            }
                        }
                    }
                }
            } finally {
                CleanupParts(partFiles);
            }
        }

        private static void CleanupParts(string[] partFiles) {
            foreach (string pf in partFiles) {
                try { if (!string.IsNullOrEmpty(pf) && File.Exists(pf)) File.Delete(pf); } catch { }
            }
        }
    }
}
'@

function Ensure-NativeModuleLoaded {
    if (-not ('SavioLangNative.FastDownloader' -as [type])) {
        Add-Type -TypeDefinition $script:NativeCSharpCode -ErrorAction Stop
    }
}

# ==============================================================================
# 4. SYSTEM INSPECTION & WINDOWS UPDATE PAUSE GUARD
# ==============================================================================
function Get-SystemLanguageState {
    param([switch]$Fast)
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $editionId = [string]$cv.EditionID
    $productName = [string]$cv.ProductName
    $buildNum = [string]$cv.CurrentBuildNumber
    $ubr = [string]$cv.UBR
    $displayVer = [string]$cv.DisplayVersion
    if (-not $displayVer) { $displayVer = [string]$cv.ReleaseId }
    $arch = Get-SystemArchNormalized

    $nls = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -ErrorAction SilentlyContinue
    $sysPref = ''
    try {
        if (Get-Command Get-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
            $sysPref = [string](Get-SystemPreferredUILanguage)
        }
    } catch { }
    $winUiOvr = ''
    try { $winUiOvr = [string](Get-WinUILanguageOverride) } catch { }
    $userList = @()
    try { $userList = @(Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) } catch { }

    $muiPacks = @()
    if ($Fast) {
        try {
            $cbsRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
            $cbsKeys = Get-ChildItem -Path $cbsRoot -ErrorAction SilentlyContinue | Where-Object {
                $_.PSChildName -like 'Microsoft-Windows-Client-LanguagePack-Package~*'
            }
            foreach ($ck in $cbsKeys) {
                $cp = Get-ItemProperty -Path $ck.PSPath -Name 'CurrentState' -ErrorAction SilentlyContinue
                # 112 (0x70) = Installed, 128 (0x80) = InstallPending
                if ($cp -and ($cp.CurrentState -eq 112 -or $cp.CurrentState -eq 128)) {
                    if ($ck.PSChildName -match '~([a-z]{2,3}(?:-[A-Za-z0-9]+)+)~') {
                        $muiPacks += $Matches[1]
                    }
                }
            }
        } catch { }
    } else {
        try {
            $pkgs = Get-WindowsPackage -Online -ErrorAction Stop | Where-Object {
                $_.PackageName -match 'Client-LanguagePack-Package' -and $_.PackageState -in @('Installed', 'InstallPending')
            }
            foreach ($p in $pkgs) {
                if ($p.PackageName -match '~([a-z]{2,3}(?:-[A-Za-z0-9]+)+)~') {
                    $muiPacks += $Matches[1]
                } elseif ($p.PackageName -match '-([a-z]{2,3}-[a-zA-Z]{2,4})\b') {
                    $muiPacks += $Matches[1]
                }
            }
        } catch { }
    }
    if ($muiPacks.Count -eq 0) {
        try {
            $muiKeys = Get-ChildItem -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages' -ErrorAction SilentlyContinue
            foreach ($k in $muiKeys) {
                $prop = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
                # Type bit 0x100 = full MUI vs LIP (0x94 = 148 = LIP, 0x111 = 273 = MUI)
                if (($prop.Type -band 0x100) -ne 0 -or $k.PSChildName -ieq 'en-US') {
                    $muiPacks += $k.PSChildName
                }
            }
        } catch { }
    }
    $muiPacks = @($muiPacks | ForEach-Object {
        try { ([System.Globalization.CultureInfo]::GetCultureInfo($_)).Name } catch { $_ }
    } | Select-Object -Unique)

    $lxpTags = @()
    try {
        $apx = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*LanguageExperiencePack*' }
        if (-not $apx -and -not $Fast) {
            $apx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*LanguageExperiencePack*' }
        }
        foreach ($a in $apx) {
            if ($a.Name -match 'LanguageExperiencePack\.?([a-zA-Z]{2,3}-?[a-zA-Z]{2,4})') {
                $rawTag = $Matches[1]
                if ($rawTag -notmatch '-' -and $rawTag.Length -eq 4) {
                    $rawTag = $rawTag.Substring(0,2) + '-' + $rawTag.Substring(2,2)
                }
                try { $lxpTags += ([System.Globalization.CultureInfo]::GetCultureInfo($rawTag)).Name } catch { $lxpTags += $rawTag }
            }
        }
    } catch { }
    $lxpTags = @($lxpTags | Select-Object -Unique)

    $installedLangs = @()
    if (-not $Fast) {
        try {
            if (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue) {
                $installedLangs = @(Get-InstalledLanguage -ErrorAction SilentlyContinue | ForEach-Object {
                    [PSCustomObject]@{
                        Id    = $_.LanguageId
                        Packs = ($_.LanguagePacks -join ',')
                    }
                })
            }
        } catch { }
    }

    $langLockExists = $false
    try {
        $q = Invoke-CapturedProcess -FilePath 'schtasks.exe' -Arguments "/Query /TN `"$($script:LangLockTaskName)`"" -TimeoutMs 15000
        $langLockExists = ($q.ExitCode -eq 0)
    } catch { }

    $isSingleLang = ($editionId -match 'SingleLanguage') -or ($productName -match 'Single Language')
    $nonEnMui = @($muiPacks | Where-Object { $_ -ine 'en-US' })
    $hasOemConflict = ($isSingleLang -and ($muiPacks.Count -gt 1 -or $nonEnMui.Count -gt 0))

    return [PSCustomObject]@{
        ProductName        = $productName
        EditionID          = $editionId
        IsSingleLanguage   = $isSingleLang
        DisplayVersion     = $displayVer
        BuildNumber        = $buildNum
        UBR                = $ubr
        Arch               = $arch
        SystemPreferredUI  = $sysPref
        WinUIOverride      = $winUiOvr
        UserLanguageList   = $userList
        NlsInstallLangHex  = [string]$nls.InstallLanguage
        NlsDefaultHex      = [string]$nls.Default
        InstalledMuiPacks  = $muiPacks
        InstalledLxpTags   = $lxpTags
        InstalledLanguages = $installedLangs
        LangLockActive     = $langLockExists
        HasOemConflict     = $hasOemConflict
    }
}

function Enter-WuUnpause {
    param([hashtable]$Sync = $null)
    $wuKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $names = @(
        'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime',
        'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime',
        'PauseUpdatesStartTime', 'PauseUpdatesExpiryTime'
    )
    $state = [ordered]@{ WasPaused = $false; Values = @{} }
    try {
        if (Test-Path -LiteralPath $wuKey) {
            $props = Get-ItemProperty -Path $wuKey -ErrorAction SilentlyContinue
            foreach ($n in $names) {
                $val = $props.$n
                if ($null -ne $val -and [string]$val -ne '') {
                    $state.Values[$n] = [string]$val
                }
            }
            if ($state.Values.ContainsKey('PauseUpdatesExpiryTime')) {
                try {
                    $exp = [datetimeoffset]::Parse($state.Values['PauseUpdatesExpiryTime'])
                    if ($exp -gt [datetimeoffset]::UtcNow) {
                        $state.WasPaused = $true
                    }
                } catch { }
            }
        }
    } catch { }

    Initialize-SavioFolders
    ($state | ConvertTo-Json -Depth 4) | Set-Content -Path $script:PauseBackupFile -Encoding Ascii

    if ($state.WasPaused) {
        Write-AppLog 'Windows Update dang Pause - tam mo de tai goi ngon ngu...' 'INFO' $Sync
        foreach ($n in $names) {
            Remove-ItemProperty -Path $wuKey -Name $n -ErrorAction SilentlyContinue
        }
    }

    # Ensure wuauserv can start if not disabled permanently
    try {
        $svc = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running' -and $svc.StartType -ne 'Disabled') {
            Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        }
    } catch { }

    return $state
}

function Exit-WuPauseRestore {
    param($BackupState, [hashtable]$Sync = $null)
    $wuKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    if ($null -eq $BackupState -and (Test-Path -LiteralPath $script:PauseBackupFile)) {
        try {
            $raw = Get-Content -LiteralPath $script:PauseBackupFile -Raw | ConvertFrom-Json
            $vals = @{}
            if ($raw.Values) {
                foreach ($p in $raw.Values.PSObject.Properties) { $vals[$p.Name] = [string]$p.Value }
            }
            $BackupState = [ordered]@{ WasPaused = [bool]$raw.WasPaused; Values = $vals }
        } catch { }
    }
    if ($BackupState -and $BackupState.WasPaused) {
        try {
            if (-not (Test-Path -LiteralPath $wuKey)) { New-Item -Path $wuKey -Force | Out-Null }
            foreach ($kv in $BackupState.Values.GetEnumerator()) {
                New-ItemProperty -Path $wuKey -Name $kv.Key -PropertyType String -Value $kv.Value -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Write-AppLog 'Da khoi phuc trang thai Pause Windows Update nhu ban dau.' 'INFO' $Sync
        } catch {
            Write-AppLog "Khong khoi phuc duoc Pause Windows Update: $($_.Exception.Message)" 'WARN' $Sync
        }
    }
    Remove-Item -LiteralPath $script:PauseBackupFile -Force -ErrorAction SilentlyContinue
}

# ==============================================================================
# 5. FAST DOWNLOAD, PACKAGE VERIFICATION & AUTOMATED ESD -> CAB CONVERTER
# ==============================================================================
function Test-DisplayPackInstalled {
    param([string]$Tag)
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag

    try {
        if (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue) {
            $l = Get-InstalledLanguage -Language $normTag -ErrorAction SilentlyContinue
            if ($null -ne $l -and (($l.LanguagePacks -join ' ') -match 'LpCab|LXP')) {
                return $true
            }
        }
    } catch { }

    try {
        $pkgs = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object {
            $_.PackageName -match 'Client-LanguagePack-Package' -and
            $_.PackageName -match [regex]::Escape($normTag) -and
            $_.PackageState -in @('Installed', 'InstallPending')
        }
        if ($pkgs) { return $true }
    } catch { }

    $key = $normTag.Replace('-', '').ToLowerInvariant()
    try {
        $apx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like '*LanguageExperiencePack*' -and
            ($_.Name.Replace('-', '').Replace('.', '').ToLowerInvariant() -like "*$key*")
        }
        if (-not $apx) {
            $apx = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -like '*LanguageExperiencePack*' -and
                ($_.Name.Replace('-', '').Replace('.', '').ToLowerInvariant() -like "*$key*")
            }
        }
        if ($apx) { return $true }
    } catch { }

    return $false
}

function Test-FullMuiInstalled {
    param([string]$Tag)
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag
    try {
        if (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue) {
            $l = Get-InstalledLanguage -Language $normTag -ErrorAction SilentlyContinue
            if ($null -ne $l -and (($l.LanguagePacks -join ' ') -match 'LpCab')) {
                return $true
            }
        }
    } catch { }
    try {
        $pkgs = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object {
            $_.PackageName -match 'Client-LanguagePack-Package' -and
            $_.PackageName -match [regex]::Escape($normTag) -and
            $_.PackageState -in @('Installed', 'InstallPending')
        }
        if ($pkgs) { return $true }
    } catch { }
    return $false
}

function Test-BasicCapabilityInstalled {
    param([string]$Tag)
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag
    try {
        $cap = Get-WindowsCapability -Online -Name "Language.Basic~~~$normTag~~~0.0.1.0" -ErrorAction SilentlyContinue
        if ($null -ne $cap -and $cap.State -in @('Installed', 'InstallPending')) { return $true }
    } catch { }
    try {
        $pkg = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object {
            $_.PackageName -match "LanguageFeatures-Basic-$([regex]::Escape($normTag))" -and
            $_.PackageState -in @('Installed', 'InstallPending')
        }
        if ($pkg) { return $true }
    } catch { }
    return $false
}

function Invoke-FastFileDownload {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$ExpectedSha256 = $null,
        [string]$Label = 'file',
        [hashtable]$Sync = $null
    )
    Ensure-NativeModuleLoaded
    Write-AppLog "Dang tai $Label (multi-connection HTTP)..." 'INFO' $Sync

    $cb = [Action[long, long, double]]{
        param($done, $total, $mbps)
        if ($null -ne $Sync) {
            $doneMb = [math]::Round($done / 1MB, 1)
            $spd = [math]::Round($mbps, 1)
            if ($total -gt 0) {
                $pct = [int][math]::Min(100, [math]::Floor(($done * 100.0) / $total))
                $totMb = [math]::Round($total / 1MB, 1)
                Set-UiProgress -Sync $Sync -Status "Dang tai $Label`: $doneMb / $totMb MB ($pct% - $spd MB/s)" -Percent $pct -Style 'Continuous'
            } else {
                Set-UiProgress -Sync $Sync -Status "Dang tai $Label`: $doneMb MB ($spd MB/s)" -Style 'Marquee'
            }
        }
    }
    $cancelFn = [Func[bool]]{
        if ($null -ne $Sync -and $Sync.CancelRequested) { return $true }
        return $false
    }

    [SavioLangNative.FastDownloader]::DownloadFile($Url, $OutFile, 4, $cb, $cancelFn)

    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Khong tim thay file sau khi tai: $OutFile"
    }
    if ($ExpectedSha256) {
        $actual = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash
        if ($actual -ine $ExpectedSha256) {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            throw "Sai SHA-256 checksum cho $Label (ky vong $ExpectedSha256, thuc te $actual)"
        }
        Write-AppLog "Da xac minh SHA-256 thanh cong cho $Label." 'OK' $Sync
    }
}

function Remove-DirectoryForceWithAcl {
    param([string]$DirPath)
    if (-not (Test-Path -LiteralPath $DirPath)) { return }
    try {
        Remove-Item -LiteralPath $DirPath -Recurse -Force -ErrorAction Stop
    } catch {
        try {
            $null = Invoke-CapturedProcess -FilePath 'cmd.exe' -Arguments "/c `"takeown /F `"`"$DirPath`"`" /R /D Y >nul 2>&1 & icacls `"`"$DirPath`"`" /grant Administrators:F /T /Q >nul 2>&1`"" -TimeoutMs 60000
            Remove-Item -LiteralPath $DirPath -Recurse -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Invoke-CapturedProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [int]$TimeoutMs = 900000
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $outSb = New-Object System.Text.StringBuilder
    $errSb = New-Object System.Text.StringBuilder

    $null = $proc.Start()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch { }
        throw "Tien trinh $FilePath qua thoi gian cho ($($TimeoutMs / 1000)s)"
    }
    [void]$outSb.Append($outTask.GetAwaiter().GetResult())
    [void]$errSb.Append($errTask.GetAwaiter().GetResult())
    return [PSCustomObject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $outSb.ToString().Trim()
        StdErr   = $errSb.ToString().Trim()
    }
}

function Install-CabPackage {
    param(
        [string]$CabPath,
        [hashtable]$Sync = $null
    )
    if (-not (Test-Path -LiteralPath $CabPath)) { throw "Khong tim thay file CAB: $CabPath" }
    $fileName = [System.IO.Path]::GetFileName($CabPath)
    Write-AppLog "Dang nap goi CAB vao Windows: $fileName ..." 'INFO' $Sync
    Set-UiProgress -Sync $Sync -Status "Dang cai dat goi $fileName (DISM)..." -Style 'Marquee'

    try {
        Add-WindowsPackage -Online -PackagePath $CabPath -NoRestart -ErrorAction Stop | Out-Null
        Write-AppLog "Da cai dat thanh cong $fileName qua Add-WindowsPackage." 'OK' $Sync
        return $true
    } catch {
        Write-AppLog "Add-WindowsPackage gap loi ($($_.Exception.Message)), thu lai bang dism.exe..." 'WARN' $Sync
        $res = Invoke-CapturedProcess -FilePath 'dism.exe' -Arguments "/Online /Add-Package /PackagePath:`"$CabPath`" /NoRestart"
        # 0 = success, 3010 = success (reboot required)
        if ($res.ExitCode -eq 0 -or $res.ExitCode -eq 3010) {
            Write-AppLog "DISM da cai dat thanh cong $fileName (ExitCode=$($res.ExitCode))." 'OK' $Sync
            return $true
        }
        $detail = if ($res.StdErr) { $res.StdErr } elseif ($res.StdOut) { ($res.StdOut -split "`r?`n" | Select-Object -Last 4) -join ' | ' } else { '' }
        throw "DISM tra ve ma loi $($res.ExitCode) khi cai $fileName ($detail)"
    }
}

function ConvertFrom-LanguageEsdToCab {
    param(
        [string]$EsdPath,
        [string]$OutCabPath = $null,
        [switch]$KeepCab,
        [hashtable]$Sync = $null
    )
    if (-not (Test-Path -LiteralPath $EsdPath)) { throw "Khong tim thay file ESD: $EsdPath" }
    Ensure-NativeModuleLoaded
    Initialize-SavioFolders

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($EsdPath)
    $guid = ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
    # Keep staging paths short so WinSxS component paths stay safely below MAX_PATH (260)
    $extractDir = Join-Path $script:StagingRoot "e_$guid"
    $ddfPath = Join-Path $script:StagingRoot "d_$guid.ddf"
    $cabOutDir = Join-Path $script:StagingRoot "c_$guid"
    $cabFileName = "$baseName.cab"
    $generatedCab = Join-Path $cabOutDir $cabFileName
    $movedOut = $false

    New-Item -ItemType Directory -Path $extractDir, $cabOutDir -Force | Out-Null
    try {
        Write-AppLog "Buoc ESD->CAB [1/3]: Dang giai nen anh ESD ($baseName)..." 'INFO' $Sync
        Set-UiProgress -Sync $Sync -Status 'Dang giai nen goi ESD (DISM Apply-Image)...' -Style 'Marquee'
        $pApply = Invoke-CapturedProcess -FilePath 'dism.exe' -Arguments "/Apply-Image /ImageFile:`"$EsdPath`" /Index:1 /ApplyDir:`"$extractDir`""
        if ($pApply.ExitCode -ne 0) {
            throw "DISM /Apply-Image that bai (ExitCode=$($pApply.ExitCode)): $($pApply.StdOut)"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $extractDir 'update.mum'))) {
            $anyMum = Get-ChildItem -LiteralPath $extractDir -Filter '*.mum' -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $anyMum) {
                throw 'File ESD khong chua cau truc goi CBS (thieu update.mum).'
            }
        }

        Write-AppLog 'Buoc ESD->CAB [2/3]: Dang giai ma WinSxS manifests (msdelta/cabinet)...' 'INFO' $Sync
        Set-UiProgress -Sync $Sync -Status 'Dang giai ma cac manifest nen (DCM/DCN/DCS)...' -Style 'Marquee'
        $expanded = [SavioLangNative.SxsExpand]::ExpandManifestDirectory($extractDir, $script:WcpSrcManifestGzipB64)
        Write-AppLog "Da giai ma $expanded file .manifest thanh cong." 'OK' $Sync

        Write-AppLog 'Buoc ESD->CAB [3/3]: Dang dong goi thanh file .CAB bang makecab.exe...' 'INFO' $Sync
        Set-UiProgress -Sync $Sync -Status 'Dang tao file .CAB chuan DISM (makecab)...' -Style 'Marquee'

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('.OPTION EXPLICIT')
        [void]$sb.AppendLine(".Set CabinetNameTemplate=$cabFileName")
        [void]$sb.AppendLine(".Set DiskDirectory1=$cabOutDir")
        [void]$sb.AppendLine('.Set CompressionType=MSZIP')
        [void]$sb.AppendLine('.Set FolderSizeThreshold=5000000')
        [void]$sb.AppendLine('.Set Cabinet=on')
        [void]$sb.AppendLine('.Set Compress=on')
        [void]$sb.AppendLine('.Set MaxDiskSize=0')
        [void]$sb.AppendLine('.Set MaxCabinetSize=0')
        [void]$sb.AppendLine('.Set InfFileName=NUL')
        [void]$sb.AppendLine('.Set RptFileName=NUL')
        [void]$sb.AppendLine('.Set UniqueFiles=OFF')

        $srcRoot = (Get-Item -LiteralPath $extractDir).FullName
        $allFiles = Get-ChildItem -LiteralPath $srcRoot -Recurse -File
        $grouped = $allFiles | Group-Object { $_.DirectoryName }
        foreach ($g in $grouped) {
            $relDir = ''
            if ($g.Name.Length -gt $srcRoot.Length) {
                $relDir = $g.Name.Substring($srcRoot.Length + 1)
            }
            [void]$sb.AppendLine(".Set DestinationDir=$relDir")
            foreach ($f in $g.Group) {
                [void]$sb.AppendLine(('"' + $f.FullName + '" "' + $f.Name + '"'))
            }
        }
        [System.IO.File]::WriteAllText($ddfPath, $sb.ToString(), [System.Text.Encoding]::ASCII)

        $pCab = Invoke-CapturedProcess -FilePath 'makecab.exe' -Arguments "/F `"$ddfPath`""
        if ($pCab.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $generatedCab)) {
            throw "makecab.exe that bai (ExitCode=$($pCab.ExitCode)): $($pCab.StdOut) $($pCab.StdErr)"
        }

        $finalCab = $generatedCab
        if ($OutCabPath) {
            $outParent = [System.IO.Path]::GetDirectoryName($OutCabPath)
            if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
                New-Item -ItemType Directory -Path $outParent -Force | Out-Null
            }
            Move-Item -LiteralPath $generatedCab -Destination $OutCabPath -Force
            $finalCab = $OutCabPath
            $movedOut = $true
        }
        if ($KeepCab) {
            $desktopCab = Join-Path ([Environment]::GetFolderPath('Desktop')) $cabFileName
            Copy-Item -LiteralPath $finalCab -Destination $desktopCab -Force
            Write-AppLog "Da luu ban sao file CAB ra Desktop: $desktopCab" 'OK' $Sync
        }

        $cabSizeMB = [math]::Round((Get-Item -LiteralPath $finalCab).Length / 1MB, 1)
        Write-AppLog "Chuyen doi ESD -> CAB hoan tat: $finalCab ($cabSizeMB MB)." 'OK' $Sync
        return $finalCab
    } finally {
        Remove-DirectoryForceWithAcl -DirPath $extractDir
        Remove-Item -LiteralPath $ddfPath -Force -ErrorAction SilentlyContinue
        if ($OutCabPath -or $movedOut -or -not (Test-Path -LiteralPath $generatedCab)) {
            Remove-DirectoryForceWithAcl -DirPath $cabOutDir
        }
    }
}

# ==============================================================================
# 6. DOWNLOAD & INSTALL SOURCES (Windows Update -> MS Store Winget -> UUPDump)
# ==============================================================================
function Find-WingetExe {
    $cmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }

    $userApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $userApps) { return $userApps }

    $progApps = Get-ChildItem -Path (Join-Path $env:ProgramFiles 'WindowsApps') -Filter 'Microsoft.DesktopAppInstaller_*' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($dir in $progApps) {
        $cand = Join-Path $dir.FullName 'winget.exe'
        if (Test-Path -LiteralPath $cand) { return $cand }
    }
    return $null
}

function Install-FromWindowsUpdate {
    param(
        [string]$Tag,
        [ValidateSet('Full', 'Display', 'Keyboard')]
        [string]$Mode,
        [hashtable]$Sync = $null
    )
    Write-AppLog "Thu tai va cai $Tag tu Windows Update..." 'INFO' $Sync
    Set-UiProgress -Sync $Sync -Status "Dang cai dat $Tag tu Windows Update..." -Style 'Marquee'

    if ($Mode -eq 'Full' -or $Mode -eq 'Keyboard') {
        try {
            $capName = "Language.Basic~~~$Tag~~~0.0.1.0"
            Add-WindowsCapability -Online -Name $capName -ErrorAction Stop | Out-Null
            Write-AppLog "Da cai dat Language.Basic ($Tag) qua Windows Update." 'OK' $Sync
        } catch {
            Write-AppLog "Add-WindowsCapability ($Tag) khong thanh cong: $($_.Exception.Message)" 'WARN' $Sync
        }
    }

    if ($Mode -eq 'Full' -or $Mode -eq 'Display') {
        if (Get-Command 'Install-Language' -ErrorAction SilentlyContinue) {
            try {
                if ($Mode -eq 'Display') {
                    Install-Language -Language $Tag -ExcludeFeatures -ErrorAction Stop | Out-Null
                } else {
                    Install-Language -Language $Tag -ErrorAction Stop | Out-Null
                }
                Write-AppLog "Install-Language ($Tag) hoan tat." 'OK' $Sync
            } catch {
                Write-AppLog "Install-Language ($Tag) khong thanh cong: $($_.Exception.Message)" 'WARN' $Sync
            }
        } else {
            Write-AppLog 'Windows nay khong co lenh Install-Language (Win 10 cu), chuyen sang kenh du phong.' 'WARN' $Sync
        }
    }
}

function Install-FromMicrosoftStore {
    param(
        [string]$Tag,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $Tag
    if (-not $meta.StoreId) { return $false }

    $winget = Find-WingetExe
    if (-not $winget) {
        Write-AppLog 'Khong tim thay winget.exe tren may, bo qua kenh Microsoft Store.' 'WARN' $Sync
        return $false
    }

    Write-AppLog "Thu cai goi LXP $Tag tu Microsoft Store qua winget ($($meta.StoreId))..." 'INFO' $Sync
    Set-UiProgress -Sync $Sync -Status "Dang tai LXP $Tag tu Microsoft Store (winget)..." -Style 'Marquee'
    try {
        $wgArgs = "install --id $($meta.StoreId) --exact --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity"
        $p = Invoke-CapturedProcess -FilePath $winget -Arguments $wgArgs -TimeoutMs 300000
        if ($p.ExitCode -ne 0) {
            Write-AppLog "winget tra ve ma $($p.ExitCode)." 'WARN' $Sync
        }
    } catch {
        Write-AppLog "winget gap loi: $($_.Exception.Message)" 'WARN' $Sync
    }
    return (Test-DisplayPackInstalled -Tag $Tag)
}

function Invoke-UupApiJson {
    param(
        [string]$Uri,
        [hashtable]$Sync = $null
    )
    $delays = @(4, 8, 14)
    for ($attempt = 0; $attempt -le $delays.Count; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Uri -UseBasicParsing -TimeoutSec 25
        } catch {
            $statusCode = $null
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
            if ($statusCode -eq 400) {
                throw $_
            }
            if (($statusCode -eq 429 -or $statusCode -ge 500 -or $null -eq $statusCode) -and $attempt -lt $delays.Count) {
                $waitSec = $delays[$attempt]
                Write-AppLog "UUPDump dang gioi han/ban (HTTP $statusCode), doi $waitSec giay roi thu lai..." 'WARN' $Sync
                Start-Sleep -Seconds $waitSec
                continue
            }
            throw $_
        }
    }
}

function Get-UupFileMap {
    param($FilesObj)
    $map = @{}
    if ($null -eq $FilesObj) { return $map }
    if ($FilesObj -is [System.Collections.IDictionary]) {
        foreach ($k in $FilesObj.Keys) { $map[[string]$k] = $FilesObj[$k] }
    } elseif ($null -ne $FilesObj.PSObject.Properties) {
        foreach ($p in $FilesObj.PSObject.Properties) { $map[$p.Name] = $p.Value }
    }
    return $map
}

function Install-FromUupDump {
    param(
        [string]$Tag,
        [ValidateSet('Full', 'Display', 'Keyboard')]
        [string]$Mode,
        [switch]$KeepCab,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag
    $tagLower = $normTag.ToLowerInvariant()
    $tagEsc = [regex]::Escape($normTag)

    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildNumber = [string]$cv.CurrentBuildNumber
    $arch = Get-SystemArchNormalized
    $fullBuild = $null
    if ($null -ne $cv.UBR) {
        try { $fullBuild = [version]"$buildNumber.$($cv.UBR)" } catch { }
    }

    Write-AppLog "Dang tim ban Windows build $buildNumber ($arch) tren UUPDump..." 'INFO' $Sync
    Set-UiProgress -Sync $Sync -Status "Dang tra cuu build $buildNumber ($arch) tren UUPDump..." -Style 'Marquee'

    $searchBuilds = @($buildNumber)
    if ($meta.IsLip -and $Mode -ne 'Keyboard' -and [int]$buildNumber -ge 22000) {
        # Win11 LIP LXP .appx fallback builds if current build lacks LXP
        $searchBuilds += @('22621', '22000', '19045')
    }

    foreach ($searchNum in ($searchBuilds | Select-Object -Unique)) {
        $list = $null
        try {
            $list = Invoke-UupApiJson -Uri "https://api.uupdump.net/listid.php?search=$searchNum" -Sync $Sync
        } catch {
            Write-AppLog "Loi truy van danh sach UUPDump ($searchNum): $($_.Exception.Message)" 'WARN' $Sync
            continue
        }
        if (-not $list -or -not $list.response -or -not $list.response.builds) { continue }

        $candidates = @()
        foreach ($prop in $list.response.builds.PSObject.Properties) {
            $b = $prop.Value
            if ($b.arch -ne $arch) { continue }
            if ($b.title -like 'Feature update to Windows*' -or
                $b.title -like 'Windows 1*, version *' -or
                $b.title -like 'Windows 11 (*' -or
                $b.title -like 'Upgrade to Windows 11*') {
                $candidates += $b
            }
        }
        if ($candidates.Count -eq 0) { continue }

        if ($searchNum -eq $buildNumber -and $null -ne $fullBuild) {
            $fitting = @($candidates | Where-Object {
                try { ([version]$_.build) -le $fullBuild } catch { $false }
            })
            if ($fitting.Count -gt 0) { $candidates = $fitting }
        }

        $ordered = @($candidates | Sort-Object { [long]$_.created } -Descending | Select-Object -First 4)
        foreach ($cand in $ordered) {
            Write-AppLog "Dang kiem tra file trong ban: $($cand.title)..." 'INFO' $Sync
            $fileMap = @{}
            $triedUrls = @(
                "https://api.uupdump.net/get.php?id=$($cand.uuid)&lang=$tagLower",
                "https://api.uupdump.net/get.php?id=$($cand.uuid)"
            )
            foreach ($u in $triedUrls) {
                try {
                    Start-Sleep -Milliseconds 1200
                    $info = Invoke-UupApiJson -Uri $u -Sync $Sync
                    $fileMap = Get-UupFileMap -FilesObj $info.response.files
                    if ($fileMap.Count -gt 0) { break }
                } catch {
                    # HTTP 400 UNSUPPORTED_LANG falls through cleanly to no-&lang= call
                }
            }
            if ($fileMap.Count -eq 0) { continue }

            $allNames = @($fileMap.Keys)
            Write-AppLog "UUPDump tra ve $($allNames.Count) file cho $($cand.title)." 'INFO' $Sync

            $installedDisplay = ($Mode -eq 'Keyboard')
            $installedBasic = ($Mode -eq 'Display')

            # 1) Keyboard / Basic FOD (.cab)
            if (($Mode -eq 'Full' -or $Mode -eq 'Keyboard') -and -not (Test-BasicCapabilityInstalled -Tag $normTag)) {
                $basicPattern = "(?i)^Microsoft-Windows-LanguageFeatures-Basic-$tagEsc-Package.*-$arch.*\.cab$"
                $basicName = $allNames | Where-Object { $_ -match $basicPattern } | Select-Object -First 1
                if (-not $basicName) {
                    $basicName = $allNames | Where-Object { $_ -match "(?i)LanguageFeatures-Basic-$tagEsc.*\.cab$" } | Select-Object -First 1
                }
                if ($basicName) {
                    $entry = $fileMap[$basicName]
                    $basicPath = Join-Path $script:StagingRoot $basicName
                    try {
                        Invoke-FastFileDownload -Url $entry.url -OutFile $basicPath -ExpectedSha256 $entry.sha256 -Label $basicName -Sync $Sync
                        $installedBasic = Install-CabPackage -CabPath $basicPath -Sync $Sync
                    } catch {
                        Write-AppLog "Loi tai/cai Basic FOD ($basicName): $($_.Exception.Message)" 'WARN' $Sync
                    } finally {
                        Remove-Item -LiteralPath $basicPath -Force -ErrorAction SilentlyContinue
                    }
                }
            } else {
                $installedBasic = $true
            }

            if ($Mode -eq 'Keyboard') {
                if ($installedBasic -or (Test-BasicCapabilityInstalled -Tag $normTag)) { return $true }
                continue
            }

            # 2) Display Pack: Check LXP (.appx) first, then CAB, then ESD (auto convert ESD -> CAB)
            if (-not (Test-DisplayPackInstalled -Tag $normTag)) {
                $lxpName = $allNames | Where-Object { $_ -match "(?i)^LanguageExperiencePack\.$tagEsc\.Neutral\.(appx|msix)$" } | Select-Object -First 1
                if ($lxpName) {
                    $entry = $fileMap[$lxpName]
                    $lxpPath = Join-Path $script:StagingRoot $lxpName
                    try {
                        Invoke-FastFileDownload -Url $entry.url -OutFile $lxpPath -ExpectedSha256 $entry.sha256 -Label $lxpName -Sync $Sync
                        Write-AppLog "Dang cai dat goi LXP $lxpName..." 'INFO' $Sync
                        Add-AppxPackage -Path $lxpPath -ErrorAction Stop
                        try { Add-AppxProvisionedPackage -Online -PackagePath $lxpPath -SkipLicense -ErrorAction SilentlyContinue | Out-Null } catch { }
                        if (Test-DisplayPackInstalled -Tag $normTag) {
                            $installedDisplay = $true
                            Write-AppLog "Da cai dat thanh cong $lxpName." 'OK' $Sync
                        }
                    } catch {
                        Write-AppLog "Loi cai LXP ($lxpName): $($_.Exception.Message)" 'WARN' $Sync
                    } finally {
                        Remove-Item -LiteralPath $lxpPath -Force -ErrorAction SilentlyContinue
                    }
                }

                if (-not $installedDisplay) {
                    $cabName = $allNames | Where-Object { $_ -match "(?i)^Microsoft-Windows-Client-LanguagePack-Package.*$tagEsc.*\.cab$" } | Select-Object -First 1
                    if ($cabName) {
                        $entry = $fileMap[$cabName]
                        $cabPath = Join-Path $script:StagingRoot $cabName
                        try {
                            Invoke-FastFileDownload -Url $entry.url -OutFile $cabPath -ExpectedSha256 $entry.sha256 -Label $cabName -Sync $Sync
                            if (Install-CabPackage -CabPath $cabPath -Sync $Sync) {
                                $installedDisplay = $true
                                if ($KeepCab) {
                                    $deskCab = Join-Path ([Environment]::GetFolderPath('Desktop')) $cabName
                                    Copy-Item -LiteralPath $cabPath -Destination $deskCab -Force
                                }
                            }
                        } catch {
                            Write-AppLog "Loi tai/cai CAB ($cabName): $($_.Exception.Message)" 'WARN' $Sync
                        } finally {
                            Remove-Item -LiteralPath $cabPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                if (-not $installedDisplay) {
                    $esdName = $allNames | Where-Object { $_ -match "(?i)^Microsoft-Windows-Client-LanguagePack-Package.*$tagEsc.*\.esd$" } | Select-Object -First 1
                    if (-not $esdName) {
                        $esdName = $allNames | Where-Object { $_ -match "(?i)$tagEsc.*\.esd$" -and $_ -match 'LanguagePack' } | Select-Object -First 1
                    }
                    if ($esdName) {
                        $entry = $fileMap[$esdName]
                        $esdPath = Join-Path $script:StagingRoot $esdName
                        $cabOutPath = Join-Path $script:StagingRoot (([System.IO.Path]::GetFileNameWithoutExtension($esdName)) + '_' + ([Guid]::NewGuid().ToString('N').Substring(0,6)) + '.cab')
                        try {
                            Invoke-FastFileDownload -Url $entry.url -OutFile $esdPath -ExpectedSha256 $entry.sha256 -Label $esdName -Sync $Sync
                            $convertedCab = ConvertFrom-LanguageEsdToCab -EsdPath $esdPath -OutCabPath $cabOutPath -KeepCab:$KeepCab -Sync $Sync
                            if (Install-CabPackage -CabPath $convertedCab -Sync $Sync) {
                                $installedDisplay = $true
                            }
                        } catch {
                            Write-AppLog "Loi chuyen doi/cai ESD ($esdName): $($_.Exception.Message)" 'ERROR' $Sync
                        } finally {
                            Remove-Item -LiteralPath $esdPath -Force -ErrorAction SilentlyContinue
                            Remove-Item -LiteralPath $cabOutPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            } else {
                $installedDisplay = $true
            }

            if ($installedDisplay) { return $true }
        }
    }
    return $false
}

function Ensure-TargetLanguageInstalled {
    param(
        [string]$Tag,
        [ValidateSet('Full', 'Display', 'Keyboard')]
        [string]$Mode,
        [switch]$KeepCab,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag

    # Pre-check: For LIP display languages (vi-VN, hi-IN, id-ID), en-US MUST be installed as base MUI!
    if ($Mode -ne 'Keyboard' -and $meta.IsLip) {
        if (-not (Test-FullMuiInstalled -Tag 'en-US')) {
            Write-AppLog "Ngon ngu $normTag la dang LIP, can goi goc en-US (Full MUI) truoc. Dang kiem tra & cai en-US..." 'WARN' $Sync
            Install-FromWindowsUpdate -Tag 'en-US' -Mode 'Display' -Sync $Sync
            if (-not (Test-FullMuiInstalled -Tag 'en-US')) {
                $null = Install-FromUupDump -Tag 'en-US' -Mode 'Display' -KeepCab:$KeepCab -Sync $Sync
            }
            if (Test-FullMuiInstalled -Tag 'en-US') {
                Write-AppLog 'Da dam bao goi goc en-US Full MUI ton tai.' 'OK' $Sync
            } else {
                Write-AppLog 'Chua cai duoc goi goc en-US Full MUI; se giu nguyen MUI goc hien co de tranh hong giao dien.' 'WARN' $Sync
            }
        }
    }

    $alreadyOk = if ($Mode -eq 'Keyboard') {
        Test-BasicCapabilityInstalled -Tag $normTag
    } elseif ($Mode -eq 'Display') {
        Test-DisplayPackInstalled -Tag $normTag
    } else {
        (Test-DisplayPackInstalled -Tag $normTag) -and (Test-BasicCapabilityInstalled -Tag $normTag)
    }
    if ($alreadyOk) {
        Write-AppLog "Goi ngon ngu $normTag da co san tren may." 'OK' $Sync
        return $true
    }

    # Tier 1: Windows Update
    Install-FromWindowsUpdate -Tag $normTag -Mode $Mode -Sync $Sync
    if ($Mode -eq 'Keyboard' -and (Test-BasicCapabilityInstalled -Tag $normTag)) { return $true }
    if ($Mode -eq 'Display' -and (Test-DisplayPackInstalled -Tag $normTag)) { return $true }
    if ($Mode -eq 'Full' -and (Test-DisplayPackInstalled -Tag $normTag) -and (Test-BasicCapabilityInstalled -Tag $normTag)) { return $true }

    # Tier 2: Microsoft Store via winget (for Display LXP)
    if ($Mode -ne 'Keyboard' -and -not (Test-DisplayPackInstalled -Tag $normTag)) {
        $null = Install-FromMicrosoftStore -Tag $normTag -Sync $Sync
    }

    # Tier 3: UUPDump + Auto ESD->CAB
    $needUup = if ($Mode -eq 'Keyboard') {
        -not (Test-BasicCapabilityInstalled -Tag $normTag)
    } else {
        (-not (Test-DisplayPackInstalled -Tag $normTag)) -or ($Mode -eq 'Full' -and -not (Test-BasicCapabilityInstalled -Tag $normTag))
    }
    if ($needUup) {
        $null = Install-FromUupDump -Tag $normTag -Mode $Mode -KeepCab:$KeepCab -Sync $Sync
    }

    if ($Mode -eq 'Keyboard') {
        return (Test-BasicCapabilityInstalled -Tag $normTag)
    }
    return (Test-DisplayPackInstalled -Tag $normTag)
}

# ==============================================================================
# 7. OEM MULTI-LANGUAGE CLEANUP, DISPLAY ENFORCEMENT & SAVIO-LANGLOCK
# ==============================================================================
function Set-SafeRegistryValue {
    param([string]$Path, [string]$Name, [string]$Type, $Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Remove-ConflictingOemPackages {
    param(
        [string]$TargetTag,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $TargetTag
    $keepTags = @('en-US', $meta.Tag) | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique

    # Safety Gate: Never delete OEM MUI packs if target is LIP and en-US Full MUI is NOT installed!
    if ($meta.IsLip -and -not (Test-FullMuiInstalled -Tag 'en-US')) {
        Write-AppLog 'AN TOAN: Khong tim thay goi en-US Full MUI nen bo qua buoc go goi ngon ngu OEM (tranh trang giao dien).' 'WARN' $Sync
        return
    }
    if (-not $meta.IsLip -and -not (Test-FullMuiInstalled -Tag $meta.Tag) -and -not (Test-FullMuiInstalled -Tag 'en-US')) {
        Write-AppLog 'AN TOAN: Chua xac nhan duoc goi Full MUI nao, bo qua go goi OEM.' 'WARN' $Sync
        return
    }

    Write-AppLog "Dang kiem tra va go cac goi ngon ngu OEM xung dot (chi giu lai: $($keepTags -join ', '))..." 'INFO' $Sync
    Set-UiProgress -Sync $Sync -Status 'Dang go goi ngon ngu OEM xung dot (ASUS/MSI fix)...' -Style 'Marquee'

    # Temporarily point system UI to en-US (if installed) so Windows releases lock on OEM MUI like th-TH/zh-CN
    if (Test-FullMuiInstalled -Tag 'en-US') {
        try {
            if (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
                Set-SystemPreferredUILanguage -Language 'en-US' -ErrorAction SilentlyContinue | Out-Null
            }
            Set-SafeRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' 'InstallLanguage' 'String' '0409'
            Set-SafeRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' 'Default' 'String' '0409'
        } catch { }
    }

    # 1) Remove conflicting Client-LanguagePack-Package CBS packages
    try {
        $pkgs = Get-WindowsPackage -Online -ErrorAction Stop | Where-Object {
            $_.PackageName -match 'Client-LanguagePack-Package' -and $_.PackageState -in @('Installed', 'InstallPending')
        }
        foreach ($p in $pkgs) {
            $pkgTag = $null
            if ($p.PackageName -match '~([a-z]{2,3}(?:-[A-Za-z0-9]+)+)~') {
                $pkgTag = $Matches[1].ToLowerInvariant()
            } elseif ($p.PackageName -match '-([a-z]{2,3}-[a-zA-Z]{2,4})\b') {
                $pkgTag = $Matches[1].ToLowerInvariant()
            }
            if ($pkgTag -and ($keepTags -notcontains $pkgTag)) {
                Write-AppLog "Dang go goi MUI OEM: $pkgTag ($($p.PackageName))..." 'INFO' $Sync
                try {
                    Remove-WindowsPackage -Online -PackageName $p.PackageName -NoRestart -ErrorAction Stop | Out-Null
                    Write-AppLog "Da go thanh cong goi MUI OEM: $pkgTag." 'OK' $Sync
                } catch {
                    Write-AppLog "Khong go duoc $pkgTag`: $($_.Exception.Message)" 'WARN' $Sync
                }
            }
        }
    } catch {
        Write-AppLog "Loi khi liet ke goi CBS de go: $($_.Exception.Message)" 'WARN' $Sync
    }

    # 2) Remove conflicting OEM LanguageExperiencePack Appx packages (e.g., pre-staged Thai/Chinese LXP)
    try {
        $apxList = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*LanguageExperiencePack*' }
        foreach ($a in $apxList) {
            $matchedKeep = $false
            foreach ($k in $keepTags) {
                $compact = $k.Replace('-', '')
                if ($a.Name.Replace('-', '').Replace('.', '').ToLowerInvariant() -like "*$compact*") {
                    $matchedKeep = $true
                    break
                }
            }
            if (-not $matchedKeep) {
                Write-AppLog "Dang go LXP OEM xung dot: $($a.Name)..." 'INFO' $Sync
                try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null } catch { }
                try {
                    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $a.Name }
                    foreach ($pr in $prov) {
                        Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction SilentlyContinue | Out-Null
                    }
                } catch { }
            }
        }
    } catch { }
}

function Set-LangLockTask {
    param(
        [string]$TargetTag,
        [string]$HexId,
        [bool]$IsLip,
        [bool]$Enable,
        [hashtable]$Sync = $null
    )
    if (-not $Enable) {
        try {
            $null = Invoke-CapturedProcess -FilePath 'schtasks.exe' -Arguments "/Delete /TN `"$($script:LangLockTaskName)`" /F" -TimeoutMs 15000
            Remove-Item -LiteralPath $script:LangLockScript -Force -ErrorAction SilentlyContinue
            Write-AppLog "Da xoa tac vu $($script:LangLockTaskName) (khong can thiet hoac nguoi dung tat)." 'INFO' $Sync
        } catch { }
        return
    }

    Initialize-SavioFolders
    $installHex = if ($IsLip) { '0409' } else { $HexId }
    $langListItems = if ($IsLip -and ($TargetTag -ine 'en-US')) { "'$TargetTag', 'en-US'" } else { "'$TargetTag'" }

    $lockContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$Target = '$TargetTag'
`$DefaultHex = '$HexId'
`$InstallHex = '$installHex'
`$LogPath = '$($script:WorkRoot)\LangLock.log'

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value `$InstallHex -Type String -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value `$DefaultHex -Type String -Force
if ('$IsLip' -eq 'True') {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguageFallback' -Value 'en-US' -Type String -Force
    `$muiPath = "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages\`$Target"
    if (Test-Path -LiteralPath `$muiPath) {
        Set-ItemProperty -Path `$muiPath -Name 'DefaultFallback' -Value 'en-US' -Type String -Force
    }
}
if (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
    Set-SystemPreferredUILanguage -Language `$Target | Out-Null
}
Set-WinUILanguageOverride -Language `$Target | Out-Null

`$existing = @(Get-WinUserLanguageList | ForEach-Object { `$_.LanguageTag })
`$newOrder = New-WinUserLanguageList -Language `$Target
foreach (`$item in @($langListItems)) {
    if (`$item -ine `$Target -and -not (`$newOrder.LanguageTag -contains `$item)) {
        `$newOrder.Add(`$item)
    }
}
foreach (`$old in `$existing) {
    if (-not (`$newOrder.LanguageTag -contains `$old)) {
        `$newOrder.Add(`$old)
    }
}
Set-WinUserLanguageList -LanguageList `$newOrder -Force | Out-Null

Add-Content -Path `$LogPath -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + " LangLock applied `$Target (Default=`$DefaultHex, Install=`$InstallHex)")
"@
    [System.IO.File]::WriteAllText($script:LangLockScript, $lockContent, (New-Object System.Text.UTF8Encoding($false)))

    $psExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
    $tr = "`"$psExe`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:LangLockScript)`""
    try {
        $null = Invoke-CapturedProcess -FilePath 'schtasks.exe' -Arguments "/Delete /TN `"$($script:LangLockTaskName)`" /F" -TimeoutMs 15000
    } catch { }
    $createArgs = "/Create /TN `"$($script:LangLockTaskName)`" /TR `"$($tr.Replace('"', '\"'))`" /SC ONLOGON /DELAY 0000:20 /RL HIGHEST /F"
    $p = Invoke-CapturedProcess -FilePath 'schtasks.exe' -Arguments $createArgs -TimeoutMs 20000
    if ($p.ExitCode -eq 0) {
        Write-AppLog "Da tao tac vu $($script:LangLockTaskName) (tre 20s sau dang nhap)." 'OK' $Sync
    } else {
        Write-AppLog "Khong tao duoc tac vu $($script:LangLockTaskName) (ExitCode=$($p.ExitCode)): $($p.StdErr)" 'WARN' $Sync
    }
}

function Apply-DisplayLanguageSettings {
    param(
        [string]$Tag,
        [bool]$RemoveOemConflicts,
        [bool]$EnableLangLock,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag
    $hexId = $meta.HexId

    if ($meta.IsLip) {
        Write-AppLog "Luu y: $normTag la goi ngon ngu dang LIP (su dung $($(if (Test-FullMuiInstalled 'en-US') { 'en-US' } else { 'MUI he thong' })) lam nen)." 'INFO' $Sync
    }

    if ($RemoveOemConflicts) {
        Remove-ConflictingOemPackages -TargetTag $normTag -Sync $Sync
    }

    Write-AppLog "Dang ap dung ngon ngu hien thi he thong ($normTag / HEX=$hexId)..." 'INFO' $Sync
    Set-UiProgress -Sync $Sync -Status "Dang cau hinh cac lop hien thi Windows cho $normTag..." -Style 'Marquee'

    # 1) Nls\Language: Critical fix! For LIP (vi-VN), InstallLanguage MUST stay on base full MUI (0409 en-US if installed)
    # so Windows doesn't reject LIP as InstallLanguage and revert to OEM MUI on boot!
    $installHex = $hexId
    if ($meta.IsLip -and (Test-FullMuiInstalled -Tag 'en-US')) {
        $installHex = '0409'
        Set-SafeRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' 'InstallLanguageFallback' 'String' 'en-US'
        $muiSub = "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages\$normTag"
        if (Test-Path -LiteralPath $muiSub) {
            Set-SafeRegistryValue $muiSub 'DefaultFallback' 'String' 'en-US'
        }
    }
    Set-SafeRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' 'InstallLanguage' 'String' $installHex
    Set-SafeRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' 'Default' 'String' $hexId

    # 2) System Preferred UI & User UI Override
    try {
        if (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
            Set-SystemPreferredUILanguage -Language $normTag -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
    try { Set-WinUILanguageOverride -Language $normTag -ErrorAction SilentlyContinue | Out-Null } catch { }

    # 3) User HKCU Registry & Ordered Language List (target first, en-US fallback for LIP, preserve other keyboards)
    try {
        Set-SafeRegistryValue 'HKCU:\Control Panel\International' 'LocaleName' 'String' $normTag
        $prefArr = if ($meta.IsLip -and ($normTag -ine 'en-US')) { @($normTag, 'en-US') } else { @($normTag) }
        Set-SafeRegistryValue 'HKCU:\Control Panel\Desktop' 'PreferredUILanguages' 'MultiString' ([string[]]$prefArr)

        $existingList = @(Get-WinUserLanguageList -ErrorAction SilentlyContinue | ForEach-Object { $_.LanguageTag })
        $newList = New-WinUserLanguageList -Language $normTag
        if ($meta.IsLip -and ($normTag -ine 'en-US') -and (Test-FullMuiInstalled -Tag 'en-US')) {
            if (-not ($newList.LanguageTag -contains 'en-US')) { $newList.Add('en-US') }
        }
        foreach ($oldTag in $existingList) {
            if (-not ($newList.LanguageTag -contains $oldTag)) {
                $newList.Add($oldTag)
            }
        }
        Set-WinUserLanguageList -LanguageList $newList -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-AppLog "Canh bao khi cap nhat danh sach ngon ngu User: $($_.Exception.Message)" 'WARN' $Sync
    }

    # 4) Sync Welcome Screen & System Accounts (prevents login screen/system fallback revert)
    try {
        if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction SilentlyContinue | Out-Null
            Write-AppLog 'Da dong bo ngon ngu ra Welcome Screen va New User Accounts.' 'OK' $Sync
        }
        if (Test-Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop') {
            $prefSys = if ($meta.IsLip -and ($normTag -ine 'en-US')) { @($normTag, 'en-US') } else { @($normTag) }
            Set-SafeRegistryValue 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop' 'PreferredUILanguages' 'MultiString' ([string[]]$prefSys)
        }
    } catch { }

    # 5) Re-register target LXP Appx manifest (fixes half-English Settings)
    try {
        $key = $normTag.Replace('-', '').ToLowerInvariant()
        $lxpPkg = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like '*LanguageExperiencePack*' -and
            ($_.Name.Replace('-', '').Replace('.', '').ToLowerInvariant() -like "*$key*")
        } | Select-Object -First 1
        if (-not $lxpPkg) {
            $lxpPkg = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -like '*LanguageExperiencePack*' -and
                ($_.Name.Replace('-', '').Replace('.', '').ToLowerInvariant() -like "*$key*")
            } | Select-Object -First 1
        }
        if ($lxpPkg -and $lxpPkg.InstallLocation) {
            $man = Join-Path $lxpPkg.InstallLocation 'AppxManifest.xml'
            if (Test-Path -LiteralPath $man) {
                Add-AppxPackage -Register -Path $man -DisableDevelopmentMode -ErrorAction SilentlyContinue
                Write-AppLog "Da dang ky lai goi LXP ($($lxpPkg.Name))." 'INFO' $Sync
            }
        }
    } catch { }

    # 6) Clear SystemSettings cache across ALL user profiles (not only elevated account)
    try {
        Get-Process -Name 'SystemSettings' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $userDirs = Get-ChildItem -Path (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction SilentlyContinue
        foreach ($ud in $userDirs) {
            $cpBase = Join-Path $ud.FullName 'AppData\Local\Packages\windows.immersivecontrolpanel_cw5n1h2txyewy'
            if (Test-Path -LiteralPath $cpBase) {
                Remove-Item -LiteralPath (Join-Path $cpBase 'LocalState') -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path $cpBase 'TempState') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }

    # 7) Trigger Windows ReconcileLanguageResources task
    try {
        $null = Invoke-CapturedProcess -FilePath 'schtasks.exe' -Arguments '/Run /TN "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources"' -TimeoutMs 15000
    } catch { }

    # 8) Manage Savio-LangLock Task
    Set-LangLockTask -TargetTag $normTag -HexId $hexId -IsLip $meta.IsLip -Enable $EnableLangLock -Sync $Sync

    # 9) Final Layer Verification
    $state = Get-SystemLanguageState
    $firstTag = if ($state.UserLanguageList.Count -gt 0) { $state.UserLanguageList[0] } else { '' }
    $tp = ($normTag -split '-')[0]
    $fp = ($firstTag -split '-')[0]
    $op = ($state.WinUIOverride -split '-')[0]
    $sp = ($state.SystemPreferredUI -split '-')[0]

    Write-AppLog "Xac nhan lop hien thi -> UserList[0]=$firstTag | Override=$($state.WinUIOverride) | SysPref=$($state.SystemPreferredUI) | InstallHex=$($state.NlsInstallLangHex) | DefaultHex=$($state.NlsDefaultHex)" 'INFO' $Sync
    if ($fp -ieq $tp -and $op -ieq $tp -and ($sp -ieq $tp -or -not $sp)) {
        Write-AppLog "HOAN TAT: Sau khi khoi dong lai may, Windows se hien thi bang $normTag." 'OK' $Sync
    } else {
        Write-AppLog 'CANH BAO: Mot so lop hien thi chua khop hoan toan. Hay khoi dong lai may va kiem tra trong Settings.' 'WARN' $Sync
    }
}

function Enable-KeyboardAndLangBar {
    param(
        [string]$Tag,
        [bool]$AddToList = $true,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag
    if ($AddToList) {
        try {
            $list = Get-WinUserLanguageList -ErrorAction SilentlyContinue
            if (-not ($list.LanguageTag -contains $normTag)) {
                $list.Add($normTag)
                Set-WinUserLanguageList -LanguageList $list -Force -ErrorAction SilentlyContinue | Out-Null
                Write-AppLog "Da them bo go $normTag vao danh sach ban phim." 'OK' $Sync
            }
        } catch { }
    }
    try {
        Set-SafeRegistryValue 'HKCU:\Software\Microsoft\CTF\LangBar' 'ShowStatus' 'DWord' 4
        Set-SafeRegistryValue 'HKCU:\Software\Microsoft\CTF\LangBar' 'ExtraIconsOnTaskbar' 'DWord' 1
        Set-SafeRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'ctfmon' 'String' "$env:SystemRoot\System32\ctfmon.exe"
        if (-not (Get-Process -Name 'ctfmon' -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath "$env:SystemRoot\System32\ctfmon.exe" -ErrorAction SilentlyContinue
        }
        Write-AppLog 'Da kich hoat thanh chuyen doi ngon ngu ban phim (ctfmon).' 'OK' $Sync
    } catch { }
}

# ==============================================================================
# 8. ORCHESTRATION WORKFLOWS (Online Install & Local ESD/CAB Install)
# ==============================================================================
function Invoke-LanguageChangeJob {
    param(
        [string]$Tag,
        [string]$Mode,
        [bool]$RemoveOem,
        [bool]$EnableLangLock,
        [bool]$ManageWuPause,
        [bool]$KeepCab,
        [hashtable]$Sync = $null
    )
    $meta = Resolve-LanguageMeta -Tag $Tag
    $normTag = $meta.Tag
    $wuBackup = $null
    try {
        Initialize-SavioFolders
        Write-AppLog "=== BAT DAU TIEN TRINH: $normTag | Che do: $Mode ===" 'INFO' $Sync

        if ($ManageWuPause) {
            $wuBackup = Enter-WuUnpause -Sync $Sync
        }

        $pkgOk = Ensure-TargetLanguageInstalled -Tag $normTag -Mode $Mode -KeepCab:$KeepCab -Sync $Sync
        if (-not $pkgOk) {
            Write-AppLog "THAT BAI: Khong tai hoac xac nhan duoc goi ngon ngu $normTag. Tool DUNG lai va KHONG thay doi Registry de tranh loi giao dien." 'ERROR' $Sync
            if ($null -ne $Sync) { $Sync.Succeeded = $false; $Sync.NeedsReboot = $false }
            return $false
        }

        if ($Mode -eq 'Keyboard') {
            Enable-KeyboardAndLangBar -Tag $normTag -AddToList $true -Sync $Sync
        } else {
            Apply-DisplayLanguageSettings -Tag $normTag -RemoveOemConflicts $RemoveOem -EnableLangLock $EnableLangLock -Sync $Sync
            if ($Mode -eq 'Full') {
                Enable-KeyboardAndLangBar -Tag $normTag -AddToList $false -Sync $Sync
            }
        }

        if ($null -ne $Sync) {
            $Sync.Succeeded = $true
            $Sync.NeedsReboot = ($Mode -ne 'Keyboard')
        }
        Write-AppLog "=== TIEN TRINH HOAN TAT CHO $normTag ===" 'OK' $Sync
        return $true
    } catch {
        Write-AppLog "LOI TRONG QUA TRINH XU LY: $($_.Exception.Message)" 'ERROR' $Sync
        if ($null -ne $Sync) { $Sync.Succeeded = $false; $Sync.NeedsReboot = $false }
        return $false
    } finally {
        if ($ManageWuPause) {
            Exit-WuPauseRestore -BackupState $wuBackup -Sync $Sync
        }
        $endPct = if ($null -ne $Sync -and $Sync.Succeeded) { 100 } else { 0 }
        Set-UiProgress -Sync $Sync -Percent $endPct -Style 'Continuous'
    }
}

function Invoke-LocalPackageJob {
    param(
        [string]$PackageFilePath,
        [string]$ApplyTag,
        [bool]$RemoveOem,
        [bool]$EnableLangLock,
        [bool]$KeepCab,
        [hashtable]$Sync = $null
    )
    try {
        Initialize-SavioFolders
        $ext = [System.IO.Path]::GetExtension($PackageFilePath).ToLowerInvariant()
        Write-AppLog "=== XU LY FILE CUC BO: $PackageFilePath ===" 'INFO' $Sync

        $installed = $false
        if ($ext -eq '.esd') {
            $cabDir = $null
            try {
                $cabPath = ConvertFrom-LanguageEsdToCab -EsdPath $PackageFilePath -KeepCab:$KeepCab -Sync $Sync
                $cabDir = [System.IO.Path]::GetDirectoryName($cabPath)
                $installed = Install-CabPackage -CabPath $cabPath -Sync $Sync
            } finally {
                if ($cabDir) { Remove-DirectoryForceWithAcl -DirPath $cabDir }
            }
        } elseif ($ext -eq '.cab') {
            $installed = Install-CabPackage -CabPath $PackageFilePath -Sync $Sync
        } elseif ($ext -eq '.appx' -or $ext -eq '.msix') {
            Add-AppxPackage -Path $PackageFilePath -ErrorAction Stop
            try { Add-AppxProvisionedPackage -Online -PackagePath $PackageFilePath -SkipLicense -ErrorAction SilentlyContinue | Out-Null } catch { }
            $installed = $true
            Write-AppLog "Da cai dat LXP cuc bo: $PackageFilePath" 'OK' $Sync
        } else {
            throw "Dinh dang file khong ho tro: $ext (chi ho tro .esd, .cab, .appx, .msix)"
        }

        if ($installed -and $ApplyTag) {
            Apply-DisplayLanguageSettings -Tag $ApplyTag -RemoveOemConflicts $RemoveOem -EnableLangLock $EnableLangLock -Sync $Sync
            Enable-KeyboardAndLangBar -Tag $ApplyTag -AddToList $false -Sync $Sync
            if ($null -ne $Sync) { $Sync.NeedsReboot = $true }
        }
        if ($null -ne $Sync) { $Sync.Succeeded = $installed }
        return $installed
    } catch {
        Write-AppLog "LOI XU LY FILE CUC BO: $($_.Exception.Message)" 'ERROR' $Sync
        if ($null -ne $Sync) { $Sync.Succeeded = $false }
        return $false
    } finally {
        $endPct = if ($null -ne $Sync -and $Sync.Succeeded) { 100 } else { 0 }
        Set-UiProgress -Sync $Sync -Percent $endPct -Style 'Continuous'
    }
}

# ==============================================================================
# 9. MODERN WINFORMS GUI (Non-Blocking Background Runspace)
# ==============================================================================
function Start-GuiApp {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $fontMain = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $fontBold = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $fontSub = New-Object System.Drawing.Font('Segoe UI', 9)
    $fontMono = New-Object System.Drawing.Font('Consolas', 9)

    $form = New-Object System.Windows.Forms.Form
    $form.SuspendLayout()
    $form.Text = T 'Savio Language Changer - Windows 10/11 (Home Single Language Ready)'
    $form.ClientSize = New-Object System.Drawing.Size(880, 700)
    $form.MinimumSize = New-Object System.Drawing.Size(800, 640)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $form.Font = $fontMain

    # --- Header Banner ---
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = 'Top'
    $pnlHeader.Height = 68
    $pnlHeader.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 8)
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(0, 103, 192)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = T 'C\u00f4ng c\u1ee5 \u0110\u1ed5i Ng\u00f4n Ng\u1eef Windows 10/11 (Home Single Language)'
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Dock = 'Top'
    $lblTitle.AutoSize = $true

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = 'by Savio'
    $lblSub.Font = $fontSub
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(220, 236, 252)
    $lblSub.Dock = 'Bottom'
    $lblSub.AutoSize = $true

    $pnlHeader.Controls.AddRange(@($lblSub, $lblTitle))

    # --- Bottom Action Bar (FlowLayout Left + Right so buttons never clip!) ---
    $pnlBottom = New-Object System.Windows.Forms.Panel
    $pnlBottom.Dock = 'Bottom'
    $pnlBottom.Height = 56
    $pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)

    $flowBottomLeft = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowBottomLeft.Dock = 'Left'
    $flowBottomLeft.AutoSize = $true
    $flowBottomLeft.WrapContents = $false
    $flowBottomLeft.Padding = New-Object System.Windows.Forms.Padding(12, 10, 0, 8)

    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = T 'B\u1eaft \u0111\u1ea7u c\u00e0i \u0111\u1eb7t'
    $btnStart.Font = $fontBold
    $btnStart.Size = New-Object System.Drawing.Size(156, 36)
    $btnStart.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $btnStart.FlatStyle = 'Flat'
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(0, 103, 192)
    $btnStart.ForeColor = [System.Drawing.Color]::White

    $btnLocal = New-Object System.Windows.Forms.Button
    $btnLocal.Text = T 'C\u00e0i t\u1eeb file ESD/CAB...'
    $btnLocal.Font = $fontMain
    $btnLocal.Size = New-Object System.Drawing.Size(165, 36)
    $btnLocal.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $btnLocal.FlatStyle = 'Flat'
    $btnLocal.BackColor = [System.Drawing.Color]::White

    $btnSaveLog = New-Object System.Windows.Forms.Button
    $btnSaveLog.Text = T 'M\u1edf file Log'
    $btnSaveLog.Font = $fontMain
    $btnSaveLog.Size = New-Object System.Drawing.Size(108, 36)
    $btnSaveLog.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $btnSaveLog.FlatStyle = 'Flat'
    $btnSaveLog.BackColor = [System.Drawing.Color]::White

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = T 'H\u1ee7y'
    $btnCancel.Font = $fontMain
    $btnCancel.Size = New-Object System.Drawing.Size(80, 36)
    $btnCancel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.BackColor = [System.Drawing.Color]::White
    $btnCancel.Enabled = $false

    $flowBottomLeft.Controls.AddRange(@($btnStart, $btnLocal, $btnSaveLog, $btnCancel))

    $flowBottomRight = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowBottomRight.Dock = 'Right'
    $flowBottomRight.AutoSize = $true
    $flowBottomRight.WrapContents = $false
    $flowBottomRight.Padding = New-Object System.Windows.Forms.Padding(0, 10, 14, 8)

    $btnReboot = New-Object System.Windows.Forms.Button
    $btnReboot.Text = T 'Kh\u1edfi \u0111\u1ed9ng l\u1ea1i'
    $btnReboot.Font = $fontBold
    $btnReboot.Size = New-Object System.Drawing.Size(136, 36)
    $btnReboot.Margin = New-Object System.Windows.Forms.Padding(0)
    $btnReboot.FlatStyle = 'Flat'
    $btnReboot.BackColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
    $btnReboot.ForeColor = [System.Drawing.Color]::White

    $flowBottomRight.Controls.Add($btnReboot)
    $pnlBottom.Controls.AddRange(@($flowBottomLeft, $flowBottomRight))

    # --- Main Content TableLayoutPanel (Auto-adjusting rows, zero clipping!) ---
    $tblBody = New-Object System.Windows.Forms.TableLayoutPanel
    $tblBody.Dock = 'Fill'
    $tblBody.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
    $tblBody.ColumnCount = 1
    $tblBody.RowCount = 3
    [void]$tblBody.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$tblBody.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$tblBody.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$tblBody.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    # Group 1: System Status
    $grpInfo = New-Object System.Windows.Forms.GroupBox
    $grpInfo.Text = T ' Tr\u1ea1ng th\u00e1i h\u1ec7 th\u1ed1ng hi\u1ec7n t\u1ea1i '
    $grpInfo.Font = $fontBold
    $grpInfo.Dock = 'Fill'
    $grpInfo.AutoSize = $true
    $grpInfo.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 10)
    $grpInfo.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $grpInfo.BackColor = [System.Drawing.Color]::White

    $tblInfo = New-Object System.Windows.Forms.TableLayoutPanel
    $tblInfo.Dock = 'Fill'
    $tblInfo.AutoSize = $true
    $tblInfo.ColumnCount = 2
    $tblInfo.RowCount = 1
    [void]$tblInfo.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$tblInfo.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))

    $pnlInfoLeft = New-Object System.Windows.Forms.Panel
    $pnlInfoLeft.Dock = 'Fill'
    $pnlInfoLeft.AutoSize = $true

    $lblSysInfo = New-Object System.Windows.Forms.Label
    $lblSysInfo.Font = $fontMain
    $lblSysInfo.Dock = 'Top'
    $lblSysInfo.AutoSize = $true
    $lblSysInfo.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 4)

    $lblOemWarn = New-Object System.Windows.Forms.Label
    $lblOemWarn.Font = $fontSub
    $lblOemWarn.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
    $lblOemWarn.Dock = 'Top'
    $lblOemWarn.AutoSize = $true
    $lblOemWarn.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

    $pnlInfoLeft.Controls.AddRange(@($lblOemWarn, $lblSysInfo))

    $flowInfoBtns = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowInfoBtns.FlowDirection = 'TopDown'
    $flowInfoBtns.AutoSize = $true
    $flowInfoBtns.WrapContents = $false
    $flowInfoBtns.Dock = 'Top'
    $flowInfoBtns.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = T 'L\u00e0m m\u1edbi'
    $btnRefresh.Font = $fontMain
    $btnRefresh.Size = New-Object System.Drawing.Size(112, 32)
    $btnRefresh.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $btnRefresh.FlatStyle = 'Flat'
    $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)

    $btnRemoveLock = New-Object System.Windows.Forms.Button
    $btnRemoveLock.Text = T 'G\u1ee1 LangLock'
    $btnRemoveLock.Font = $fontMain
    $btnRemoveLock.Size = New-Object System.Drawing.Size(112, 32)
    $btnRemoveLock.Margin = New-Object System.Windows.Forms.Padding(0)
    $btnRemoveLock.FlatStyle = 'Flat'
    $btnRemoveLock.BackColor = [System.Drawing.Color]::FromArgb(254, 242, 242)
    $btnRemoveLock.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)

    $flowInfoBtns.Controls.AddRange(@($btnRefresh, $btnRemoveLock))
    $tblInfo.Controls.Add($pnlInfoLeft, 0, 0)
    $tblInfo.Controls.Add($flowInfoBtns, 1, 0)
    $grpInfo.Controls.Add($tblInfo)

    # Group 2: Configuration
    $grpConfig = New-Object System.Windows.Forms.GroupBox
    $grpConfig.Text = T ' C\u1ea5u h\u00ecnh c\u00e0i \u0111\u1eb7t ng\u00f4n ng\u1eef '
    $grpConfig.Font = $fontBold
    $grpConfig.Dock = 'Fill'
    $grpConfig.AutoSize = $true
    $grpConfig.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 10)
    $grpConfig.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $grpConfig.BackColor = [System.Drawing.Color]::White

    $tblCfg = New-Object System.Windows.Forms.TableLayoutPanel
    $tblCfg.Dock = 'Fill'
    $tblCfg.AutoSize = $true
    $tblCfg.ColumnCount = 1
    $tblCfg.RowCount = 5
    [void]$tblCfg.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    for ($r = 0; $r -lt 5; $r++) {
        [void]$tblCfg.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    }

    # Row 0: Language selector + custom code
    $tblLangRow = New-Object System.Windows.Forms.TableLayoutPanel
    $tblLangRow.Dock = 'Top'
    $tblLangRow.AutoSize = $true
    $tblLangRow.ColumnCount = 4
    $tblLangRow.RowCount = 1
    $tblLangRow.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 6)
    [void]$tblLangRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$tblLangRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 62)))
    [void]$tblLangRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$tblLangRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 38)))

    $lblLang = New-Object System.Windows.Forms.Label
    $lblLang.Text = T 'Ch\u1ecdn ng\u00f4n ng\u1eef \u0111\u00edch:'
    $lblLang.Font = $fontMain
    $lblLang.AutoSize = $true
    $lblLang.Anchor = 'Left'
    $lblLang.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)

    $cmbLang = New-Object System.Windows.Forms.ComboBox
    $cmbLang.Font = $fontMain
    $cmbLang.DropDownStyle = 'DropDownList'
    $cmbLang.Dock = 'Fill'
    $cmbLang.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
    foreach ($item in $script:LanguageCatalog) {
        $tagType = if ($item.IsLip) { 'LIP' } else { 'MUI' }
        [void]$cmbLang.Items.Add((T "$($item.NameUi) [$($item.Tag) - $tagType]"))
    }
    $cmbLang.SelectedIndex = 0

    $lblCustomTag = New-Object System.Windows.Forms.Label
    $lblCustomTag.Text = T 'Ho\u1eb7c m\u00e3 kh\u00e1c:'
    $lblCustomTag.Font = $fontMain
    $lblCustomTag.AutoSize = $true
    $lblCustomTag.Anchor = 'Left'
    $lblCustomTag.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)

    $txtCustomTag = New-Object System.Windows.Forms.TextBox
    $txtCustomTag.Font = $fontMain
    $txtCustomTag.Dock = 'Fill'
    $txtCustomTag.Margin = New-Object System.Windows.Forms.Padding(0)

    $tblLangRow.Controls.Add($lblLang, 0, 0)
    $tblLangRow.Controls.Add($cmbLang, 1, 0)
    $tblLangRow.Controls.Add($lblCustomTag, 2, 0)
    $tblLangRow.Controls.Add($txtCustomTag, 3, 0)

    # Row 1: Mode radio buttons
    $flowMode = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowMode.Dock = 'Top'
    $flowMode.AutoSize = $true
    $flowMode.WrapContents = $true
    $flowMode.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 6)

    $lblMode = New-Object System.Windows.Forms.Label
    $lblMode.Text = T 'Ph\u01b0\u01a1ng th\u1ee9c c\u00e0i:'
    $lblMode.Font = $fontMain
    $lblMode.AutoSize = $true
    $lblMode.Margin = New-Object System.Windows.Forms.Padding(0, 3, 14, 0)

    $rbFull = New-Object System.Windows.Forms.RadioButton
    $rbFull.Text = T 'C\u00e0i \u0111\u1ea7y \u0111\u1ee7 (Giao di\u1ec7n + B\u1ed9 g\u00f5)'
    $rbFull.Font = $fontMain
    $rbFull.AutoSize = $true
    $rbFull.Margin = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)
    $rbFull.Checked = $true

    $rbDisplay = New-Object System.Windows.Forms.RadioButton
    $rbDisplay.Text = T 'Ch\u1ec9 Giao di\u1ec7n hi\u1ec3n th\u1ecb (UI)'
    $rbDisplay.Font = $fontMain
    $rbDisplay.AutoSize = $true
    $rbDisplay.Margin = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)

    $rbKey = New-Object System.Windows.Forms.RadioButton
    $rbKey.Text = T 'Ch\u1ec9 B\u1ed9 g\u00f5 b\u00e0n ph\u00edm'
    $rbKey.Font = $fontMain
    $rbKey.AutoSize = $true

    $flowMode.Controls.AddRange(@($lblMode, $rbFull, $rbDisplay, $rbKey))

    # Row 2, 3, 4: Checkboxes
    $chkRemoveOem = New-Object System.Windows.Forms.CheckBox
    $chkRemoveOem.Text = T 'G\u1ee1 g\u00f3i ng\u00f4n ng\u1eef OEM xung \u0111\u1ed9t (ch\u1ec9 gi\u1eef en-US + ng\u00f4n ng\u1eef \u0111\u00edch - Fix m\u00e1y ASUS/MSI t\u1ef1 v\u1ec1 ti\u1ebfng Th\u00e1i)'
    $chkRemoveOem.Font = $fontMain
    $chkRemoveOem.AutoSize = $true
    $chkRemoveOem.Margin = New-Object System.Windows.Forms.Padding(2, 2, 0, 3)
    $chkRemoveOem.Checked = $true

    $chkLangLock = New-Object System.Windows.Forms.CheckBox
    $chkLangLock.Text = T 'B\u1eadt t\u00e1c v\u1ee5 gi\u1eef ng\u00f4n ng\u1eef khi kh\u1edfi \u0111\u1ed9ng (Savio-LangLock - khuy\u00ean d\u00f9ng cho LIP tr\u00ean Home SL)'
    $chkLangLock.Font = $fontMain
    $chkLangLock.AutoSize = $true
    $chkLangLock.Margin = New-Object System.Windows.Forms.Padding(2, 2, 0, 3)
    $chkLangLock.Checked = $true

    $flowChkBottom = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowChkBottom.Dock = 'Top'
    $flowChkBottom.AutoSize = $true
    $flowChkBottom.WrapContents = $true
    $flowChkBottom.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)

    $chkWuPause = New-Object System.Windows.Forms.CheckBox
    $chkWuPause.Text = T 'T\u1ea1m m\u1edf Windows Update n\u1ebfu \u0111ang Pause'
    $chkWuPause.Font = $fontMain
    $chkWuPause.AutoSize = $true
    $chkWuPause.Margin = New-Object System.Windows.Forms.Padding(2, 0, 24, 0)
    $chkWuPause.Checked = $true

    $chkKeepCab = New-Object System.Windows.Forms.CheckBox
    $chkKeepCab.Text = T 'L\u01b0u b\u1ea3n sao file .CAB ra Desktop sau khi convert ESD'
    $chkKeepCab.Font = $fontMain
    $chkKeepCab.AutoSize = $true
    $chkKeepCab.Checked = $false

    $flowChkBottom.Controls.AddRange(@($chkWuPause, $chkKeepCab))

    $tblCfg.Controls.Add($tblLangRow, 0, 0)
    $tblCfg.Controls.Add($flowMode, 0, 1)
    $tblCfg.Controls.Add($chkRemoveOem, 0, 2)
    $tblCfg.Controls.Add($chkLangLock, 0, 3)
    $tblCfg.Controls.Add($flowChkBottom, 0, 4)
    $grpConfig.Controls.Add($tblCfg)

    # Group 3: Progress & Log (use && so WinForms displays literal '&')
    $grpLog = New-Object System.Windows.Forms.GroupBox
    $grpLog.Text = T ' Ti\u1ebfn tr\u00ecnh && Nh\u1eadt k\u00fd x\u1eed l\u00fd '
    $grpLog.Font = $fontBold
    $grpLog.Dock = 'Fill'
    $grpLog.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 10)
    $grpLog.Margin = New-Object System.Windows.Forms.Padding(0)
    $grpLog.BackColor = [System.Drawing.Color]::White

    $tblLog = New-Object System.Windows.Forms.TableLayoutPanel
    $tblLog.Dock = 'Fill'
    $tblLog.ColumnCount = 1
    $tblLog.RowCount = 3
    [void]$tblLog.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$tblLog.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$tblLog.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$tblLog.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = T 'S\u1eb5n s\u00e0ng.'
    $lblStatus.Font = $fontMain
    $lblStatus.Dock = 'Fill'
    $lblStatus.AutoSize = $true
    $lblStatus.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)

    $prgBar = New-Object System.Windows.Forms.ProgressBar
    $prgBar.Dock = 'Fill'
    $prgBar.Height = 18
    $prgBar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $prgBar.Style = 'Continuous'

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Font = $fontMono
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 27)
    $txtLog.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 231)
    $txtLog.Dock = 'Fill'
    $txtLog.Margin = New-Object System.Windows.Forms.Padding(0)

    $tblLog.Controls.Add($lblStatus, 0, 0)
    $tblLog.Controls.Add($prgBar, 0, 1)
    $tblLog.Controls.Add($txtLog, 0, 2)
    $grpLog.Controls.Add($tblLog)

    $tblBody.Controls.Add($grpInfo, 0, 0)
    $tblBody.Controls.Add($grpConfig, 0, 1)
    $tblBody.Controls.Add($grpLog, 0, 2)

    $form.Controls.AddRange(@($tblBody, $pnlHeader, $pnlBottom))
    $form.ResumeLayout($false)
    $form.PerformLayout()

    # --- Helpers for GUI State ---
    $getSelectedTag = {
        $custom = $txtCustomTag.Text.Trim()
        if ($custom) { return $custom }
        $idx = $cmbLang.SelectedIndex
        if ($idx -lt 0) { $idx = 0 }
        return $script:LanguageCatalog[$idx].Tag
    }

    # --- Synchronized Background Runspace State ---
    $sync = [hashtable]::Synchronized(@{
        LogQueue        = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
        StatusText      = T 'S\u1eb5n s\u00e0ng.'
        ProgressPercent = 0
        ProgressStyle   = 'Continuous'
        IsRunning       = $false
        Succeeded       = $false
        NeedsReboot     = $false
        CancelRequested = $false
        ActivePs        = $null
        AsyncHandle     = $null
        DiagPs          = $null
        DiagHandle      = $null
        DiagResult      = $null
        DiagError       = $null
    })

    $script:CachedIsSingleLang = $false
    try {
        $cvQuick = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $nlsQuick = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -ErrorAction SilentlyContinue
        $script:CachedIsSingleLang = ($cvQuick.EditionID -match 'SingleLanguage') -or ($cvQuick.ProductName -match 'Single Language')
        $slQuick = if ($script:CachedIsSingleLang) { 'Single Language' } else { [string]$cvQuick.EditionID }
        $archQuick = Get-SystemArchNormalized
        $lblSysInfo.Text = (T "OS: $($cvQuick.ProductName) ($slQuick) | Build $($cvQuick.CurrentBuildNumber).$($cvQuick.UBR) ($archQuick)`r`n") +
                           (T "NLS Install=$($nlsQuick.InstallLanguage) Default=$($nlsQuick.Default)`r`n") +
                           (T '\u0110ang qu\u00e9t c\u00e1c g\u00f3i ng\u00f4n ng\u1eef v\u00e0 t\u00e1c v\u1ee5 tr\u00ean m\u00e1y...')
    } catch { }

    $applyDiagState = {
        param($st)
        if ($null -eq $st) { return }
        $script:CachedIsSingleLang = [bool]$st.IsSingleLanguage
        $muiStr = if ($st.InstalledMuiPacks.Count -gt 0) { $st.InstalledMuiPacks -join ', ' } else { '(Chua ro)' }
        $lxpStr = if ($st.InstalledLxpTags.Count -gt 0) { $st.InstalledLxpTags -join ', ' } else { 'Khong' }
        $lockStr = if ($st.LangLockActive) { 'Dang BAT' } else { 'Tat' }
        $slBadge = if ($st.IsSingleLanguage) { 'Single Language' } else { $st.EditionID }

        $u0 = if ($st.UserLanguageList -and $st.UserLanguageList.Count -gt 0) { $st.UserLanguageList[0] } else { '(none)' }
        $lblSysInfo.Text = (T "OS: $($st.ProductName) ($slBadge) | Build $($st.BuildNumber).$($st.UBR) ($($st.Arch))`r`n") +
                           (T "UI hi\u1ec7n t\u1ea1i: SysPref=$($st.SystemPreferredUI) | Override=$($st.WinUIOverride) | User[0]=$u0 | NLS Install=$($st.NlsInstallLangHex) Default=$($st.NlsDefaultHex)`r`n") +
                           (T "G\u00f3i \u0111\u00e3 c\u00e0i: MUI=[$muiStr] | LXP=[$lxpStr] | Savio-LangLock: $lockStr")

        if ($st.HasOemConflict) {
            $lblOemWarn.Text = T "C\u1ea3nh b\u00e1o: Ph\u00e1t hi\u1ec7n nhi\u1ec1u g\u00f3i MUI OEM ($muiStr) tr\u00ean Home SL - n\u00ean b\u1eadt t\u00f9y ch\u1ecdn g\u1ee1 g\u00f3i xung \u0111\u1ed9t."
        } else {
            $lblOemWarn.Text = ''
        }
        $btnRemoveLock.Enabled = $st.LangLockActive
        & $syncDefaultsForLanguage
    }

    $refreshDiagnosticsAsync = {
        if ($null -ne $sync.DiagHandle) { return }
        $btnRefresh.Enabled = $false
        $sync.DiagResult = $null
        $sync.DiagError = $null

        $drs = [runspacefactory]::CreateRunspace()
        $drs.ApartmentState = 'MTA'
        $drs.Open()
        $dps = [powershell]::Create()
        $dps.Runspace = $drs

        $diagBoot = @"
`$ErrorActionPreference = 'Stop'
`$script:LangLockTaskName = '$($script:LangLockTaskName)'
"@
        $diagFns = @('Get-SystemArchNormalized', 'Invoke-CapturedProcess', 'Get-SystemLanguageState') | ForEach-Object {
            "function $_ {`r`n$((Get-Item "Function:\$_").Definition)`r`n}"
        }
        [void]$dps.AddScript($diagBoot + "`r`n" + ($diagFns -join "`r`n"))
        [void]$dps.AddScript({
            param($s)
            try {
                $s.DiagResult = Get-SystemLanguageState -Fast
            } catch {
                $s.DiagError = $_.Exception.Message
            }
        })
        [void]$dps.AddArgument($sync)
        $sync.DiagPs = $dps
        $sync.DiagHandle = $dps.BeginInvoke()
    }

    $syncDefaultsForLanguage = {
        $tag = & $getSelectedTag
        try {
            $meta = Resolve-LanguageMeta -Tag $tag
            $chkLangLock.Checked = $meta.IsLip
            $chkRemoveOem.Checked = ($meta.IsLip -or $script:CachedIsSingleLang)
        } catch { }
    }

    $cmbLang.Add_SelectedIndexChanged($syncDefaultsForLanguage)
    $txtCustomTag.Add_TextChanged($syncDefaultsForLanguage)
    $btnRefresh.Add_Click($refreshDiagnosticsAsync)

    $btnRemoveLock.Add_Click({
        Set-LangLockTask -TargetTag 'en-US' -HexId '0409' -IsLip $false -Enable $false
        $txtLog.AppendText("[INFO] Da go bo tac vu Savio-LangLock.`r`n")
        & $refreshDiagnosticsAsync
    })

    $btnSaveLog.Add_Click({
        Initialize-SavioFolders
        if (-not (Test-Path -LiteralPath $script:LogFile)) {
            [System.IO.File]::WriteAllText($script:LogFile, "Log khoi tao luc $(Get-Date)`r`n")
        }
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:LogFile + '"')
    })

    $btnReboot.Add_Click({
        $ans = [System.Windows.Forms.MessageBox]::Show(
            (T 'B\u1ea1n c\u00f3 mu\u1ed1n kh\u1edfi \u0111\u1ed9ng l\u1ea1i m\u00e1y t\u00ednh ngay b\u00e2y gi\u1edd \u0111\u1ec3 \u00e1p d\u1ee5ng ng\u00f4n ng\u1eef m\u1edbi kh\u00f4ng?'),
            (T 'X\u00e1c nh\u1eadn kh\u1edfi \u0111\u1ed9ng l\u1ea1i'),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/r', '/t', '3') -NoNewWindow
            $form.Close()
        }
    })

    $setUiBusy = {
        param([bool]$Busy)
        $btnStart.Enabled = -not $Busy
        $btnLocal.Enabled = -not $Busy
        $btnRefresh.Enabled = -not $Busy
        $cmbLang.Enabled = -not $Busy
        $txtCustomTag.Enabled = -not $Busy
        $rbFull.Enabled = -not $Busy
        $rbDisplay.Enabled = -not $Busy
        $rbKey.Enabled = -not $Busy
        $chkRemoveOem.Enabled = -not $Busy
        $chkLangLock.Enabled = -not $Busy
        $chkWuPause.Enabled = -not $Busy
        $chkKeepCab.Enabled = -not $Busy
        $btnCancel.Enabled = $Busy
    }

    $uiTimer = New-Object System.Windows.Forms.Timer
    $uiTimer.Interval = 120
    $uiTimer.Add_Tick({
        $msg = $null
        $batch = New-Object System.Text.StringBuilder
        while ($sync.LogQueue.TryDequeue([ref]$msg)) {
            [void]$batch.AppendLine($msg)
        }
        if ($batch.Length -gt 0) {
            $txtLog.AppendText($batch.ToString())
        }

        if ($lblStatus.Text -ne $sync.StatusText) {
            $lblStatus.Text = $sync.StatusText
        }
        if ($sync.ProgressStyle -eq 'Marquee') {
            if ($prgBar.Style -ne [System.Windows.Forms.ProgressBarStyle]::Marquee) {
                $prgBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
            }
        } else {
            if ($prgBar.Style -ne [System.Windows.Forms.ProgressBarStyle]::Continuous) {
                $prgBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            }
            $pct = [Math]::Min(100, [Math]::Max(0, [int]$sync.ProgressPercent))
            if ($prgBar.Value -ne $pct) { $prgBar.Value = $pct }
        }

        if ($null -ne $sync.DiagHandle -and $sync.DiagHandle.IsCompleted) {
            try { $sync.DiagPs.EndInvoke($sync.DiagHandle) } catch { }
            try { $sync.DiagPs.Runspace.Close() } catch { }
            try { $sync.DiagPs.Runspace.Dispose() } catch { }
            try { $sync.DiagPs.Dispose() } catch { }
            $sync.DiagPs = $null
            $sync.DiagHandle = $null
            if (-not $sync.IsRunning) { $btnRefresh.Enabled = $true }
            if ($sync.DiagResult) {
                & $applyDiagState $sync.DiagResult
            } elseif ($sync.DiagError) {
                $lblSysInfo.Text = "Khong doc duoc trang thai he thong: $($sync.DiagError)"
            }
        }

        if ($sync.IsRunning -and $sync.AsyncHandle -and $sync.AsyncHandle.IsCompleted) {
            try { $sync.ActivePs.EndInvoke($sync.AsyncHandle) } catch {
                $txtLog.AppendText("[RUNSPACE EXCEPTION] $($_.Exception.Message)`r`n")
            }
            if ($sync.ActivePs.HadErrors -and $sync.ActivePs.Streams.Error.Count -gt 0) {
                foreach ($errRec in $sync.ActivePs.Streams.Error) {
                    $txtLog.AppendText("[RUNSPACE ERROR] $($errRec.ToString())`r`n")
                }
            }
            try { $sync.ActivePs.Runspace.Close() } catch { }
            try { $sync.ActivePs.Runspace.Dispose() } catch { }
            try { $sync.ActivePs.Dispose() } catch { }
            $sync.ActivePs = $null
            $sync.AsyncHandle = $null
            $sync.IsRunning = $false
            & $setUiBusy $false
            & $refreshDiagnosticsAsync

            if ($sync.Succeeded) {
                $lblStatus.Text = T 'Ho\u00e0n t\u1ea5t th\u00e0nh c\u00f4ng!'
                if ($sync.NeedsReboot) {
                    $ans = [System.Windows.Forms.MessageBox]::Show(
                        (T 'C\u00e0i \u0111\u1eb7t v\u00e0 \u00e1p d\u1ee5ng ng\u00f4n ng\u1eef ho\u00e0n t\u1ea5t! B\u1ea1n n\u00ean KH\u1edeI \u0110\u1ed8NG L\u1ea0I m\u00e1y t\u00ednh ngay \u0111\u1ec3 giao di\u1ec7n m\u1edbi c\u00f3 hi\u1ec7u l\u1ef1c.\r\n\r\nKh\u1edfi \u0111\u1ed9ng l\u1ea1i ngay b\u00e2y gi\u1edd?'),
                        (T 'Ho\u00e0n t\u1ea5t'),
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
                        Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/r', '/t', '3') -NoNewWindow
                        $form.Close()
                    }
                } else {
                    [System.Windows.Forms.MessageBox]::Show((T 'C\u00e0i \u0111\u1eb7t ho\u00e0n t\u1ea5t!'), (T 'Th\u00e0nh c\u00f4ng'), 'OK', 'Information') | Out-Null
                }
            } else {
                $lblStatus.Text = T 'Qu\u00e1 tr\u00ecnh g\u1eb7p l\u1ed7i ho\u1eb7c b\u1ecb h\u1ee7y. Xem nh\u1eadt k\u00fd b\u00ean d\u01b0\u1edbi.'
            }
        }
    })
    $uiTimer.Start()

    $launchWorker = {
        param([scriptblock]$WorkerScript, [object[]]$WorkerArgs)
        if ($sync.IsRunning) { return }
        $sync.IsRunning = $true
        $sync.Succeeded = $false
        $sync.NeedsReboot = $false
        $sync.CancelRequested = $false
        $sync.ProgressPercent = 0
        $sync.ProgressStyle = 'Marquee'
        & $setUiBusy $true

        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        # Pass current script functions and variables into runspace cleanly
        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        $bootstrap = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$script:WorkRoot = '$($script:WorkRoot)'
`$script:StagingRoot = '$($script:StagingRoot)'
`$script:LogDir = '$($script:LogDir)'
`$script:LogFile = '$($script:LogFile)'
`$script:PauseBackupFile = '$($script:PauseBackupFile)'
`$script:LangLockTaskName = '$($script:LangLockTaskName)'
`$script:LangLockScript = '$($script:LangLockScript)'
`$script:WcpSrcManifestGzipB64 = '$($script:WcpSrcManifestGzipB64)'
`$script:LanguageCatalog = @(
    @{ Tag = 'vi-VN'; NameAscii = 'Tieng Viet'; NameUi = 'Ti\u1ebfng Vi\u1ec7t (Vi\u1ec7t Nam)'; HexId = '042a'; StoreId = '9P0W68X0XZPT'; IsLip = `$true; BaseMui = 'en-US' }
    @{ Tag = 'en-US'; NameAscii = 'Tieng Anh - My'; NameUi = 'Ti\u1ebfng Anh - M\u1ef9 (English US)'; HexId = '0409'; StoreId = '9PDSCC711RVF'; IsLip = `$false; BaseMui = 'en-US' }
    @{ Tag = 'en-GB'; NameAscii = 'Tieng Anh - Anh'; NameUi = 'Ti\u1ebfng Anh - Anh (English UK)'; HexId = '0809'; StoreId = '9NT52VQ39BVN'; IsLip = `$false; BaseMui = 'en-GB' }
    @{ Tag = 'ja-JP'; NameAscii = 'Tieng Nhat Ban'; NameUi = 'Ti\u1ebfng Nh\u1eadt B\u1ea3n (Japanese)'; HexId = '0411'; StoreId = '9N1W692FV4S1'; IsLip = `$false; BaseMui = 'ja-JP' }
    @{ Tag = 'ko-KR'; NameAscii = 'Tieng Han Quoc'; NameUi = 'Ti\u1ebfng H\u00e0n Qu\u1ed1c (Korean)'; HexId = '0412'; StoreId = '9N4TXPCVRNGF'; IsLip = `$false; BaseMui = 'ko-KR' }
    @{ Tag = 'zh-CN'; NameAscii = 'Tieng Trung - Gian'; NameUi = 'Ti\u1ebfng Trung - Gi\u1ea3n th\u1ec3 (Simplified)'; HexId = '0804'; StoreId = '9NRMNT6GMZ70'; IsLip = `$false; BaseMui = 'zh-CN' }
    @{ Tag = 'zh-TW'; NameAscii = 'Tieng Trung - Phon'; NameUi = 'Ti\u1ebfng Trung - Ph\u1ed3n th\u1ec3 (Traditional)'; HexId = '0404'; StoreId = '9PCJ4DHCQ1JQ'; IsLip = `$false; BaseMui = 'zh-TW' }
    @{ Tag = 'th-TH'; NameAscii = 'Tieng Thai Lan'; NameUi = 'Ti\u1ebfng Th\u00e1i Lan (Thai)'; HexId = '041e'; StoreId = '9MSTWFRL0LR4'; IsLip = `$false; BaseMui = 'th-TH' }
    @{ Tag = 'fr-FR'; NameAscii = 'Tieng Phap'; NameUi = 'Ti\u1ebfng Ph\u00e1p (French)'; HexId = '040c'; StoreId = '9NHMG4BJKMDG'; IsLip = `$false; BaseMui = 'fr-FR' }
    @{ Tag = 'de-DE'; NameAscii = 'Tieng Duc'; NameUi = 'Ti\u1ebfng \u0110\u1ee9c (German)'; HexId = '0407'; StoreId = '9P6CT0SLW589'; IsLip = `$false; BaseMui = 'de-DE' }
    @{ Tag = 'ru-RU'; NameAscii = 'Tieng Nga'; NameUi = 'Ti\u1ebfng Nga (Russian)'; HexId = '0419'; StoreId = '9NMJCX77QKPX'; IsLip = `$false; BaseMui = 'ru-RU' }
    @{ Tag = 'es-ES'; NameAscii = 'Tieng Tay Ban Nha'; NameUi = 'Ti\u1ebfng T\u00e2y Ban Nha (Spanish)'; HexId = '0c0a'; StoreId = '9NWVGWLHPB1Z'; IsLip = `$false; BaseMui = 'es-ES' }
    @{ Tag = 'pt-BR'; NameAscii = 'Tieng Bo Dao Nha'; NameUi = 'Ti\u1ebfng B\u1ed3 \u0110\u00e0o Nha (Brazil)'; HexId = '0416'; StoreId = '9P8LBDM4FW35'; IsLip = `$false; BaseMui = 'pt-BR' }
    @{ Tag = 'it-IT'; NameAscii = 'Tieng Y'; NameUi = 'Ti\u1ebfng \u00dd (Italian)'; HexId = '0410'; StoreId = '9P8PQWNS6VJX'; IsLip = `$false; BaseMui = 'it-IT' }
    @{ Tag = 'id-ID'; NameAscii = 'Tieng Indonesia'; NameUi = 'Ti\u1ebfng Indonesia'; HexId = '0421'; StoreId = '9P4X3N4SDK8P'; IsLip = `$true; BaseMui = 'en-US' }
    @{ Tag = 'hi-IN'; NameAscii = 'Tieng An Do'; NameUi = 'Ti\u1ebfng \u1ea4n \u0110\u1ed9 (Hindi)'; HexId = '0439'; StoreId = '9NZC3GRX8LD3'; IsLip = `$true; BaseMui = 'en-US' }
)
`$script:LogWriteLock = New-Object object
`$script:NativeCSharpCode = @'
$($script:NativeCSharpCode)
'@
"@
        $fnNames = @(
            'T', 'Initialize-SavioFolders', 'Write-AppLog', 'Set-UiProgress',
            'Resolve-LanguageMeta', 'Get-SystemArchNormalized', 'Ensure-NativeModuleLoaded',
            'Get-SystemLanguageState', 'Enter-WuUnpause', 'Exit-WuPauseRestore',
            'Test-DisplayPackInstalled', 'Test-FullMuiInstalled', 'Test-BasicCapabilityInstalled',
            'Invoke-FastFileDownload', 'Remove-DirectoryForceWithAcl', 'Invoke-CapturedProcess', 'Install-CabPackage',
            'ConvertFrom-LanguageEsdToCab', 'Find-WingetExe', 'Install-FromWindowsUpdate',
            'Install-FromMicrosoftStore', 'Invoke-UupApiJson', 'Get-UupFileMap',
            'Install-FromUupDump', 'Ensure-TargetLanguageInstalled',
            'Set-SafeRegistryValue', 'Remove-ConflictingOemPackages', 'Set-LangLockTask',
            'Apply-DisplayLanguageSettings', 'Enable-KeyboardAndLangBar',
            'Invoke-LanguageChangeJob', 'Invoke-LocalPackageJob'
        )
        $fnDefs = ($fnNames | ForEach-Object {
            $def = (Get-Item "Function:\$_").Definition
            "function $_ {`r`n$def`r`n}"
        }) -join "`r`n"

        [void]$ps.AddScript($bootstrap + "`r`n" + $fnDefs)
        [void]$ps.AddScript($WorkerScript.ToString())
        foreach ($arg in $WorkerArgs) {
            [void]$ps.AddArgument($arg)
        }
        $sync.ActivePs = $ps
        $sync.AsyncHandle = $ps.BeginInvoke()
    }

    $btnCancel.Add_Click({
        if ($sync.IsRunning) {
            $sync.CancelRequested = $true
            $sync.StatusText = T 'Dang y\u00eau c\u1ea7u h\u1ee7y...'
            $btnCancel.Enabled = $false
        }
    })

    $btnStart.Add_Click({
        $tag = & $getSelectedTag
        try {
            $null = Resolve-LanguageMeta -Tag $tag
        } catch {
            [System.Windows.Forms.MessageBox]::Show((T "M\u00e3 ng\u00f4n ng\u1eef kh\u00f4ng h\u1ee3p l\u1ec7: $tag (v\u00ed d\u1ee5 h\u1ee3p l\u1ec7: vi-VN, ja-JP, fr-FR)"), (T 'L\u1ed7i'), 'OK', 'Warning') | Out-Null
            return
        }
        $selMode = if ($rbKey.Checked) { 'Keyboard' } elseif ($rbDisplay.Checked) { 'Display' } else { 'Full' }
        $remOem = [bool]$chkRemoveOem.Checked
        $useLock = [bool]$chkLangLock.Checked
        $useWu = [bool]$chkWuPause.Checked
        $saveCab = [bool]$chkKeepCab.Checked

        $txtLog.Clear()
        & $launchWorker {
            param($t, $m, $ro, $ul, $wu, $kc, $s)
            Invoke-LanguageChangeJob -Tag $t -Mode $m -RemoveOem $ro -EnableLangLock $ul -ManageWuPause $wu -KeepCab $kc -Sync $s
        } @($tag, $selMode, $remOem, $useLock, $useWu, $saveCab, $sync)
    })

    $btnLocal.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = T 'Ch\u1ecdn file g\u00f3i ng\u00f4n ng\u1eef (.esd, .cab, .appx, .msix)'
        $ofd.Filter = 'Language Packages (*.esd;*.cab;*.appx;*.msix)|*.esd;*.cab;*.appx;*.msix|All files (*.*)|*.*'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $filePath = $ofd.FileName
        $guessTag = & $getSelectedTag
        $fileName = [System.IO.Path]::GetFileName($filePath)
        foreach ($c in $script:LanguageCatalog) {
            if ($fileName -match [regex]::Escape($c.Tag)) { $guessTag = $c.Tag; break }
        }
        $ans = [System.Windows.Forms.MessageBox]::Show(
            (T "C\u00e0i \u0111\u1eb7t file: $fileName`r`nN\u1ebfu l\u00e0 file .ESD, tool s\u1ebd t\u1ef1 \u0111\u1ed9ng chuy\u1ec3n sang .CAB r\u1ed3i n\u1ea1p v\u00e0o Windows.`r`n\r\nC\u00f3 \u00e1p d\u1ee5ng lu\u00f4n giao di\u1ec7n cho m\u00e3 [$guessTag] sau khi c\u00e0i xong kh\u00f4ng?"),
            (T 'C\u00e0i t\u1eeb file c\u1ee5c b\u1ed9'),
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($ans -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
        $applyTag = if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { $guessTag } else { '' }
        $remOem = [bool]$chkRemoveOem.Checked
        $useLock = [bool]$chkLangLock.Checked
        $saveCab = [bool]$chkKeepCab.Checked

        $txtLog.Clear()
        & $launchWorker {
            param($fp, $at, $ro, $ul, $kc, $s)
            Invoke-LocalPackageJob -PackageFilePath $fp -ApplyTag $at -RemoveOem $ro -EnableLangLock $ul -KeepCab $kc -Sync $s
        } @($filePath, $applyTag, $remOem, $useLock, $saveCab, $sync)
    })

    $form.Add_Shown({
        & $syncDefaultsForLanguage
        $form.Activate()
        $form.Update()
        & $refreshDiagnosticsAsync
    })
    $form.Add_FormClosing({
        param($sender, $e)
        if ($sync.IsRunning) {
            $e.Cancel = $true
            [System.Windows.Forms.MessageBox]::Show((T 'Ti\u1ebfn tr\u00ecnh \u0111ang ch\u1ea1y! Vui l\u00f2ng \u0111\u1ee3i ho\u00e0n t\u1ea5t ho\u1eb7c b\u1ea5m H\u1ee7y tr\u01b0\u1edbc khi \u0111\u00f3ng.'), (T '\u0110ang x\u1eed l\u00fd'), 'OK', 'Warning') | Out-Null
            return
        }
        $uiTimer.Stop()
        $uiTimer.Dispose()
    })

    [void]$form.ShowDialog()
}

# ==============================================================================
# 10. CLI MENU / UNATTENDED ENTRYPOINT
# ==============================================================================
function Start-CliMenu {
    while ($true) {
        Clear-Host
        $st = Get-SystemLanguageState
        Write-Host '=====================================================================' -ForegroundColor Cyan
        Write-Host '   CHANGE LANGUAGE WINDOWS 10/11 HOME SL (100% Pure PowerShell)      ' -ForegroundColor Cyan
        Write-Host '=====================================================================' -ForegroundColor Cyan
        Write-Host "OS: $($st.ProductName) | Build $($st.BuildNumber).$($st.UBR) ($($st.Arch))"
        $cliU0 = if ($st.UserLanguageList -and $st.UserLanguageList.Count -gt 0) { $st.UserLanguageList[0] } else { '(none)' }
        Write-Host "UI: SysPref=$($st.SystemPreferredUI) | Override=$($st.WinUIOverride) | User[0]=$cliU0"
        Write-Host "MUI da cai: $($st.InstalledMuiPacks -join ', ') | LXP: $($st.InstalledLxpTags -join ', ')"
        Write-Host '---------------------------------------------------------------------'
        for ($i = 0; $i -lt $script:LanguageCatalog.Count; $i += 2) {
            $l1 = $script:LanguageCatalog[$i]
            $col1 = ('  [{0,2}] {1,-22} ({2})' -f ($i + 1), $l1.NameAscii, $l1.Tag)
            if ($i + 1 -lt $script:LanguageCatalog.Count) {
                $l2 = $script:LanguageCatalog[$i + 1]
                $col2 = ('|  [{0,2}] {1,-22} ({2})' -f ($i + 2), $l2.NameAscii, $l2.Tag)
                Write-Host "$col1 $col2"
            } else {
                Write-Host $col1
            }
        }
        Write-Host ''
        Write-Host '  [L] Cai tu file .ESD/.CAB/.APPX cuc bo   [R] Go Savio-LangLock   [0] Thoat'
        Write-Host '====================================================================='
        $choice = (Read-Host 'Nhap lua chon').Trim()
        if ($choice -eq '0') { return }
        if ($choice -match '^[Rr]$') {
            Set-LangLockTask -TargetTag 'en-US' -HexId '0409' -IsLip $false -Enable $false
            Read-Host 'Nhan Enter de tiep tuc'
            continue
        }
        if ($choice -match '^[Ll]$') {
            $fp = (Read-Host 'Nhap duong dan file .esd/.cab/.appx').Trim('"')
            $at = (Read-Host 'Nhap ma ngon ngu de ap dung UI (bo trong neu chi cai goi)').Trim()
            $null = Invoke-LocalPackageJob -PackageFilePath $fp -ApplyTag $at -RemoveOem $true -EnableLangLock $true -KeepCab:$KeepCab
            Read-Host 'Nhan Enter de tiep tuc'
            continue
        }
        $num = 0
        if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $script:LanguageCatalog.Count) {
            $sel = $script:LanguageCatalog[$num - 1]
            Write-Host ''
            Write-Host "Da chon: $($sel.NameAscii) ($($sel.Tag))"
            Write-Host '  [1] Cai day du (Giao dien + Bo go)  [2] Chi Giao dien  [3] Chi Bo go  [0] Quay lai'
            $m = (Read-Host 'Chon phuong thuc (1-3)').Trim()
            if ($m -eq '0') { continue }
            $modeStr = switch ($m) { '2' { 'Display' }; '3' { 'Keyboard' }; default { 'Full' } }
            $ok = Invoke-LanguageChangeJob -Tag $sel.Tag -Mode $modeStr -RemoveOem:(-not $SkipOemCleanup) -EnableLangLock:($sel.IsLip -and -not $SkipLangLock) -ManageWuPause:(-not $DisableWuUnpause) -KeepCab:$KeepCab
            if ($ok -and $modeStr -ne 'Keyboard') {
                $rb = (Read-Host 'Ban co muon KHOI DONG LAI ngay bay gio? (Y/N)').Trim()
                if ($rb -match '^(Y|YES)$') {
                    Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/r', '/t', '5') -NoNewWindow
                    return
                }
            }
            Read-Host 'Nhan Enter de quay lai menu'
        }
    }
}

# ==============================================================================
# MAIN ENTRYPOINT
# ==============================================================================
Initialize-SavioFolders

if ($Language) {
    $meta = Resolve-LanguageMeta -Tag $Language
    $useLock = ($meta.IsLip -and -not $SkipLangLock)
    $ok = Invoke-LanguageChangeJob -Tag $meta.Tag -Mode $Mode -RemoveOem:(-not $SkipOemCleanup) -EnableLangLock $useLock -ManageWuPause:(-not $DisableWuUnpause) -KeepCab:$KeepCab
    if (-not $ok) { exit 1 }
    exit 0
}

if ($NoGui) {
    Start-CliMenu
    exit 0
}

try {
    Start-GuiApp
} catch {
    Write-AppLog "Khong khoi tao duoc giao dien WinForms ($($_.Exception.Message)), chuyen sang menu CLI..." 'WARN'
    Start-CliMenu
}
