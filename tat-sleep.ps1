# tat-sleep.ps1
# Tat che do Sleep (Never) cho tat ca power profiles cua Windows
# Cach dung: mo PowerShell voi quyen Administrator (Run as Administrator) roi chay file nay

$schemes = powercfg /list | Select-String 'GUID:\s*([0-9a-fA-F-]{36})' | ForEach-Object { $_.Matches.Groups[1].Value } | Select-Object -Unique

if (-not $schemes) {
    Write-Host "Khong tim thay power profile nao." -ForegroundColor Red
    exit 1
}

foreach ($guid in $schemes) {
    powercfg /setacvalueindex $guid SUB_SLEEP STANDBYIDLE 0
    powercfg /setdcvalueindex $guid SUB_SLEEP STANDBYIDLE 0
    powercfg /setacvalueindex $guid SUB_SLEEP HIBERNATEIDLE 0
    powercfg /setdcvalueindex $guid SUB_SLEEP HIBERNATEIDLE 0
    Write-Host "Da chinh: $guid"
}

Write-Host "Xong - Sleep = Never cho tat ca profiles." -ForegroundColor Green
