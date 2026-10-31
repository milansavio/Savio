# toi-uu-win.ps1 - DON DEP & TOI UU HE THONG, PowerShell version of Bimaster_CleanUp.bat
# Run as Administrator (the script self-elevates if it is not):
#   irm https://raw.githubusercontent.com/milansavio/Savio/main/toi-uu-win.ps1 | iex
#
# Menu, in the same order as the .bat:
#   1 Don file tam thoi he thong
#   2 Xoa cache Windows Update
#   3 Don cache trinh duyet
#   4 Chay Disk Cleanup (nang cao)
#   5 Sua loi he thong (SFC/DISM)
#   6 Quan ly quyen so huu
#   7 Quan ly Windows Update
#   8 Xoa cache card man hinh
#   9 Toi uu ung dung CAD/Office
#   A Cai dat phan mem & Driver
#   B Huong dan nang cao
#   C Tao diem khoi phuc he thong
#   D Quan ly ung dung khoi dong
#   E Kiem tra suc khoe o cung
#   0 Thoat
#
# Important differences from the .bat, on purpose:
#   - The .bat only exits with a message if it is not run as Administrator.
#     This script re-launches itself as Administrator via UAC instead.
#   - Console is green text on black, like the .bat color 0A.
#   - Browser cache: the .bat deletes the whole Firefox Profiles folder
#     contents, which would destroy profiles, bookmarks and logins, not just
#     cache. This script cleans only cache folders inside each Firefox
#     profile (cache2, startupCache), and leaves the profile itself alone.
#   - The SMB optimisation inside menu 9 is the .bat version: it turns guest
#     auth OFF (AllowInsecureGuestAuth = 0) and SMB1 OFF. That is the opposite
#     of off-smb.ps1, which turns guest ON for old NAS devices. Running menu
#     9-5 after off-smb.ps1 will turn guest off again. A warning is printed
#     before that step runs.
#   - Software download links are kept exactly as in the .bat. Some are old
#     (Notepad++ 8.6.8, Snappy Driver R2201) and may be outdated; the script
#     reports a download failure instead of silently continuing.

try {
    $Host.UI.RawUI.BackgroundColor = [ConsoleColor]::Black
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::Green
    $Host.UI.RawUI.WindowTitle = 'DON DEP & TOI UU HE THONG - BIMASTER JSC'
    Clear-Host
} catch { }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'toi-uu-win: dang xin quyen Administrator, vui long bam Yes o bang UAC...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'irm https://raw.githubusercontent.com/milansavio/Savio/main/toi-uu-win.ps1 | iex'
    exit
}

function Show-Header($Title) {
    Clear-Host
    Write-Host ''
    Write-Host '    ================================================'
    Write-Host '      DON DEP & TOI UU HE THONG - BIMASTER JSC'
    Write-Host '    ================================================'
    Write-Host ''
    Write-Host "        DANG THUC HIEN: $Title"
    Write-Host ''
    Write-Host '    ================================================'
    Write-Host ''
}

function Show-Result($Text) {
    Write-Host ''
    Write-Host '    ================================================'
    Write-Host "        $Text"
    Write-Host '    ================================================'
    Write-Host ''
    Start-Sleep -Seconds 2
}

function Clean-Folder($Path) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not (Test-Path $expanded)) { return }
    Write-Host "Dang don: $expanded"
    try { Remove-Item "$expanded\*" -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

function Clean-FirefoxCache {
    $profilesRoot = [Environment]::ExpandEnvironmentVariables('%APPDATA%\Mozilla\Firefox\Profiles')
    if (-not (Test-Path $profilesRoot)) { return }
    Get-ChildItem $profilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Clean-Folder "$($_.FullName)\cache2"
        Clean-Folder "$($_.FullName)\startupCache"
        Clean-Folder "$($_.FullName)\shader-cache"
    }
}

function Clean-TempGroup {
    Show-Header 'DANG DON FILE TAM THOI'
    Clean-Folder '%TEMP%'
    Clean-Folder 'C:\Windows\Temp'
    Clean-Folder 'C:\Windows\Prefetch'
    Clean-Folder '%USERPROFILE%\AppData\Local\Temp'
    Show-Result 'Da don xong file tam thoi'
}

function Clean-WUpdate {
    Show-Header 'DANG XOA CACHE WINDOWS UPDATE'
    try { Stop-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue } catch { }
    Clean-Folder 'C:\Windows\SoftwareDistribution\Download'
    try { Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Da xoa cache Windows Update'
}

function Clean-Browsers {
    Show-Header 'DANG DON CACHE TRINH DUYET'
    Clean-Folder '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache'
    Clean-Folder '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Code Cache'
    Clean-FirefoxCache
    Clean-Folder '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache'
    Clean-Folder '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Code Cache'
    Show-Result 'Da don cache trinh duyet'
}

function Run-DiskCleanup {
    Show-Header 'DISK CLEANUP NANG CAO'
    Write-Host 'Dang phan tich o dia...'
    Write-Host 'Luu y: cleanmgr /sageset se mo bang chon danh muc lan dau, chon xong roi dong lai de chay.'
    try { Start-Process 'cleanmgr.exe' -ArgumentList '/sageset:65535' -Wait -ErrorAction SilentlyContinue } catch { }
    try { Start-Process 'cleanmgr.exe' -ArgumentList '/sagerun:65535' -Wait -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Hoan tat don dep o dia'
}

function Run-SystemRepair {
    Show-Header 'DANG KIEM TRA HE THONG'
    Write-Host ''
    Write-Host '[~] Dang chay SFC /scannow...'
    try { sfc /scannow } catch { Write-Host "SFC loi: $($_.Exception.Message)" }
    Write-Host ''
    Write-Host '[~] Dang chay DISM...'
    try { Dism /Online /Cleanup-Image /RestoreHealth } catch { Write-Host "DISM loi: $($_.Exception.Message)" }
    Show-Result 'Da hoan thanh kiem tra he thong'
}

function Run-TakeOwnership {
    Show-Header 'THAY DOI QUYEN SO HUU'
    Write-Host ''
    Write-Host 'CHI DUNG CHO FILE CA NHAN!'
    $filePath = Read-Host 'Nhap duong dan'
    if ([string]::IsNullOrWhiteSpace($filePath)) { return }
    $filePath = $filePath.Trim().Trim('"')
    if (-not (Test-Path $filePath)) {
        Write-Host 'Duong dan khong ton tai!'
        Start-Sleep -Seconds 2
        return
    }
    if (Test-Path $filePath -PathType Container) {
        takeown /f "$filePath" /r /d y | Out-Null
        icacls "$filePath" /grant administrators:F /t | Out-Null
        Write-Host 'Da ap dung cho THU MUC'
    } else {
        takeown /f "$filePath" | Out-Null
        icacls "$filePath" /grant administrators:F | Out-Null
        Write-Host 'Da ap dung cho TEP TIN'
    }
    Start-Sleep -Seconds 2
}

function Manage-WinUpdate {
    while ($true) {
        Show-Header 'QUAN LY WINDOWS UPDATE'
        Write-Host '    1 - TAT Windows Update'
        Write-Host '    2 - BAT Windows Update'
        Write-Host '    3 - KIEM TRA BAN CAP NHAT'
        Write-Host '    0 - Quay lai menu chinh'
        $c = (Read-Host 'Chon [0-3]').Trim().ToUpper()
        if ($c -eq '0') { return }
        if ($c -eq '1') {
            try { Stop-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue } catch { }
            try { Set-Service -Name 'wuauserv' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
            Show-Result 'Da tat dich vu Update'
            return
        }
        if ($c -eq '2') {
            try { Set-Service -Name 'wuauserv' -StartupType Automatic -ErrorAction SilentlyContinue } catch { }
            try { Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue } catch { }
            Show-Result 'Da bat dich vu Update'
            return
        }
        if ($c -eq '3') {
            Show-Header 'KIEM TRA BAN CAP NHAT'
            Write-Host 'Dang kiem tra ban cap nhat...'
            try { usoclient StartInteractiveScan } catch { Write-Host "usoclient loi: $($_.Exception.Message)" }
            Show-Result 'Hoan tat kiem tra cap nhat'
            return
        }
    }
}

function Clean-GpuCache {
    Show-Header 'XOA CACHE CARD MAN HINH'
    Write-Host ''
    Write-Host 'Luu y: Dong tat ca ung dung/game truoc khi thuc hien!'
    Write-Host ''
    Clean-Folder '%USERPROFILE%\AppData\Local\NVIDIA\DXCache'
    Clean-Folder '%USERPROFILE%\AppData\Local\NVIDIA\GLCache'
    Clean-Folder '%USERPROFILE%\AppData\Local\AMD\DxCache'
    Clean-Folder '%USERPROFILE%\AppData\Local\AMD\GLCache'
    Clean-Folder '%USERPROFILE%\AppData\LocalLow\AMD\DxCache'
    Clean-Folder '%USERPROFILE%\AppData\Local\Intel\ShaderCache'
    Clean-Folder '%USERPROFILE%\AppData\Local\D3DSCache'
    Show-Result 'Da xoa cache card man hinh'
}

function Optimize-Cad {
    Show-Header 'TOI UU AUTOCAD/REVIT/ARCHICAD'
    Write-Host 'Dang ap dung toi uu do hoa CAD...'
    try { Set-ItemProperty -Path 'HKCU:\Software\Autodesk\AutoCAD' -Name 'HardwareAcceleration' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Autodesk\Revit' -Name 'UseGraphicsHardware' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\GRAPHISOFT' -Name 'OpenGLEnabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type String -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '10' -Type String -Force -ErrorAction SilentlyContinue } catch { }
    try { Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue; Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
    try { Stop-Service -Name 'WerSvc' -Force -ErrorAction SilentlyContinue; Set-Service -Name 'WerSvc' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Da ap dung toi uu CAD'
}

function Optimize-Office {
    Show-Header 'TOI UU MS OFFICE'
    Write-Host 'Dang toi uu MS Word/Excel...'
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Office\16.0\Common' -Name 'DisableHardwareAcceleration' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Office\16.0\Common' -Name 'DisableAnimations' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Office\16.0\Word\Options' -Name 'NoReReg' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    Write-Host ''
    $printer = (Read-Host 'Ban co dung may in? (Y/N)').Trim().ToUpper()
    if ($printer -eq 'N') {
        try { Stop-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue; Set-Service -Name 'Spooler' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
        Write-Host 'Da tat dich vu in an'
    }
    Show-Result 'Da ap dung toi uu Office'
}

function Optimize-Print {
    Show-Header 'TOI UU DICH VU IN'
    Write-Host 'Dang quan ly dich vu in...'
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' -Name 'NetPrinterDecayPeriod' -Value 600000 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' -Name 'DisableWebPnPDownload' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Restart-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Da toi uu dich vu in'
}

function Optimize-Teams {
    Show-Header 'TOI UU MICROSOFT TEAMS'
    Write-Host 'Dang toi uu Microsoft Teams...'
    try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'com.squirrel.Teams.Teams' -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Teams' -Name 'disablegpu' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Teams' -Name 'disableanimations' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Teams' -Name 'MemoryUsageLimitInMB' -Value 2048 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Da toi uu Microsoft Teams'
}

function Optimize-Smb {
    Show-Header 'TOI UU SMB FILE SHARING'
    Write-Host 'Dang toi uu ket noi mang SMB...'
    Write-Host 'CHU Y: Muc nay TAT guest auth (AllowInsecureGuestAuth = 0), nguoc voi off-smb.ps1 (BAT guest).'
    Write-Host 'Neu ban can NAS guest, dung off-smb.ps1 sau muc nay.'
    try { Stop-Service -Name 'LanmanWorkstation' -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'AllowInsecureGuestAuth' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Start-Service -Name 'LanmanWorkstation' -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB2' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'MaxCmds' -Value 65535 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'MaxThreads' -Value 1000 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Da toi uu ket noi SMB'
}

function Optimize-SystemTweaks {
    Show-Header 'TOI UU HIEU NANG HE THONG'
    Write-Host 'Dang ap dung toi uu he thong...'
    try { Set-Service -Name 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
    try { Set-Service -Name 'TrkWks' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
    try { Set-Service -Name 'WSearch' -StartupType Disabled -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'IoPageLockLimit' -Value 524288 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type String -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '10' -Type String -Force -ErrorAction SilentlyContinue } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue } catch { }
    Show-Result 'Da ap dung toi uu he thong'
}

function Manage-AppOptimization {
    while ($true) {
        Show-Header 'TOI UU UNG DUNG CAD & OFFICE'
        Write-Host '    1 - Toi uu AutoCAD/Revit/Archicad'
        Write-Host '    2 - Toi uu MS Office (Word/Excel)'
        Write-Host '    3 - Toi uu Print Service'
        Write-Host '    4 - Toi uu Microsoft Teams'
        Write-Host '    5 - Toi uu SMB File Sharing'
        Write-Host '    6 - Toi uu hieu nang he thong'
        Write-Host '    X - Quay lai menu chinh'
        $c = (Read-Host 'Chon [1-6,X]').Trim().ToUpper()
        if ($c -eq 'X') { return }
        if ($c -eq '1') { Optimize-Cad }
        if ($c -eq '2') { Optimize-Office }
        if ($c -eq '3') { Optimize-Print }
        if ($c -eq '4') { Optimize-Teams }
        if ($c -eq '5') { Optimize-Smb }
        if ($c -eq '6') { Optimize-SystemTweaks }
    }
}

function Install-Software($Url, $OutFile, $Args) {
    Show-Header "DANG TAI $OutFile"
    Write-Host "Dang tai tu: $Url"
    try { Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop } catch { Write-Host "Tai that bai: $($_.Exception.Message)"; return $false }
    if (-not (Test-Path $OutFile)) { Write-Host 'Tai that bai: khong co file.'; return $false }
    Write-Host 'Dang cai dat...'
    try { Start-Process -FilePath $OutFile -ArgumentList $Args -Wait -ErrorAction Stop } catch { Write-Host "Cai dat loi: $($_.Exception.Message)"; return $false }
    return $true
}

function Manage-SoftwareInstall {
    while ($true) {
        Show-Header 'CAI DAT PHAN MEM & DRIVER'
        Write-Host '    1 - Cai Microsoft Edge'
        Write-Host '    2 - Cai Microsoft Teams (Desktop)'
        Write-Host '    3 - Cai Notepad++'
        Write-Host '    4 - Khoi phuc Windows Photo Viewer (cu)'
        Write-Host '    5 - Khoi phuc Windows Calculator'
        Write-Host '    6 - Cai driver bang Snappy Driver'
        Write-Host '    X - Quay lai menu chinh'
        $c = (Read-Host 'Chon [1-6,X]').Trim().ToUpper()
        if ($c -eq 'X') { return }
        if ($c -eq '1') {
            $f = "$env:TEMP\MicrosoftEdgeSetup.exe"
            if (Install-Software 'https://go.microsoft.com/fwlink/?linkid=2108834&Channel=Stable&language=vi&brand=M100' $f @('/silent', '/install')) { Show-Result 'Da cai dat Microsoft Edge' } else { Show-Result 'Tai Microsoft Edge that bai' }
        }
        if ($c -eq '2') {
            $f = "$env:TEMP\TeamsSetup.exe"
            if (Install-Software 'https://go.microsoft.com/fwlink/?linkid=2196106' $f @('-s')) { Show-Result 'Da cai dat Microsoft Teams' } else { Show-Result 'Tai Microsoft Teams that bai' }
        }
        if ($c -eq '3') {
            $f = "$env:TEMP\npp_installer.exe"
            if (Install-Software 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.8/npp.8.6.8.Installer.x64.exe' $f @('/S')) { Show-Result 'Da cai dat Notepad++' } else { Show-Result 'Tai Notepad++ that bai' }
        }
        if ($c -eq '4') {
            Show-Header 'KHOI PHUC WINDOWS PHOTO VIEWER'
            Write-Host 'Dang khoi phuc Windows Photo Viewer...'
            $assoc = @{ '.jpg' = 'PhotoViewer.FileAssoc.Jpeg'; '.jpeg' = 'PhotoViewer.FileAssoc.Jpeg'; '.jpe' = 'PhotoViewer.FileAssoc.Jpeg'; '.jfif' = 'PhotoViewer.FileAssoc.Jpeg'; '.png' = 'PhotoViewer.FileAssoc.Png'; '.bmp' = 'PhotoViewer.FileAssoc.Bitmap'; '.tiff' = 'PhotoViewer.FileAssoc.Tiff'; '.tif' = 'PhotoViewer.FileAssoc.Tiff' }
            foreach ($k in $assoc.Keys) { try { Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations' -Name $k -Value $assoc[$k] -Type String -Force -ErrorAction SilentlyContinue } catch { } }
            Show-Result 'Da khoi phuc Windows Photo Viewer'
        }
        if ($c -eq '5') {
            Show-Header 'KHOI PHUC WINDOWS CALCULATOR'
            Write-Host 'Dang khoi phuc Windows Calculator...'
            try { Get-AppxPackage *windowscalculator* | Remove-AppxPackage -ErrorAction SilentlyContinue } catch { }
            try { Get-AppxPackage -AllUsers *windowscalculator* | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue } } catch { }
            Show-Result 'Da khoi phuc Windows Calculator'
        }
        if ($c -eq '6') {
            Show-Header 'CAI DRIVER BANG SNAPPY DRIVER'
            Write-Host 'Dang tai Snappy Driver Installer...'
            $zip = "$env:TEMP\sdi.zip"
            try { Invoke-WebRequest -Uri 'https://sdi-tool.org/download/SDI_R2201.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop } catch { Show-Result 'Tai Snappy Driver that bai'; continue }
            if (Test-Path $zip) {
                Write-Host 'Dang giai nen...'
                try { Expand-Archive -Path $zip -DestinationPath "$env:TEMP\SDI" -Force -ErrorAction Stop } catch { }
                Write-Host 'Dang khoi chay...'
                try { Start-Process "$env:TEMP\SDI\SDI_R2201.exe" -ErrorAction Stop } catch { }
                Show-Result 'Da khoi dong Snappy Driver'
            } else { Show-Result 'Tai Snappy Driver that bai' }
        }
    }
}

function Show-GpuGuide {
    Show-Header 'HUONG DAN NANG CAO'
    Write-Host ''
    Write-Host '  [1] Tai DDU tu Guru3D'
    Write-Host '  [2] Khoi dong vao Safe Mode'
    Write-Host '  [3] Chay DDU de go driver'
    Write-Host '  [4] Cai driver moi'
    Write-Host '  [5] Xoa Shader Cache'
    Write-Host ''
    Write-Host '  URL: https://www.guru3d.com/files-details/display-driver-uninstaller-download.html'
    Write-Host ''
    Start-Sleep -Seconds 10
}

function New-RestorePoint {
    Show-Header 'TAO DIEM KHOI PHUC HE THONG'
    Write-Host 'Dang tao diem khoi phuc...'
    try { Checkpoint-Computer -Description 'Bimaster_CleanUp_RestorePoint' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; Show-Result 'Da tao diem khoi phuc thanh cong' } catch { Show-Result "Tao diem khoi phuc loi (co the System Restore dang tat): $($_.Exception.Message)" }
}

function Open-StartupManager {
    Show-Header 'QUAN LY UNG DUNG KHOI DONG'
    Write-Host 'Dang mo Task Manager...'
    try { Start-Process 'taskmgr.exe' -ArgumentList '/0', '/startup' -ErrorAction Stop } catch { }
    Show-Result 'Da mo Task Manager'
}

function Manage-DiskHealth {
    while ($true) {
        Show-Header 'KIEM TRA SUC KHOE O CUNG'
        Write-Host ''
        Write-Host '  [1] Kiem tra SMART'
        Write-Host '  [2] Quet loi o cung (chkdsk)'
        Write-Host '  [3] Phan tich dung luong o dia'
        Write-Host '  [0] Quay lai menu chinh'
        $c = (Read-Host 'Chon [0-3]').Trim()
        if ($c -eq '0') { return }
        if ($c -eq '1') {
            Show-Header 'KIEM TRA SMART'
            try { Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Format-Table DeviceID, Model, Status -AutoSize | Out-String | Write-Host } catch { try { wmic diskdrive get status } catch { } }
            Write-Host ''
            Write-Host 'Neu tat ca hien thi "OK" - o cung hoat dong tot'
            Write-Host 'Neu co bat ky "Bad" nao - can kiem tra ngay'
            Write-Host ''
            Read-Host 'Nhan Enter de quay lai'
            return
        }
        if ($c -eq '2') {
            Show-Header 'QUET LOI O CUNG'
            Write-Host ''
            Write-Host 'Yeu cau khoi dong lai he thong'
            Write-Host ''
            $yn = (Read-Host 'Tiep tuc? (Y/N)').Trim().ToUpper()
            if ($yn -ne 'Y') { return }
            try { chkdsk C: /f /r } catch { }
            Write-Host ''
            Write-Host 'He thong se khoi dong lai sau 30 giay...'
            shutdown /r /t 30
            Show-Result 'Da len lich kiem tra o dia'
            return
        }
        if ($c -eq '3') {
            Show-Header 'PHAN TICH DUNG LUONG'
            Write-Host 'Dang phan tich...'
            try { Start-Process 'cleanmgr.exe' -ArgumentList '/d', 'C' -ErrorAction SilentlyContinue } catch { }
            Show-Result 'Da mo Disk Cleanup'
            return
        }
    }
}

while ($true) {
    Show-Header 'MENU CHINH'
    Write-Host '     1 - Don file tam thoi he thong'
    Write-Host '     2 - Xoa cache Windows Update'
    Write-Host '     3 - Don cache trinh duyet'
    Write-Host '     4 - Chay Disk Cleanup (nang cao)'
    Write-Host '     5 - Sua loi he thong (SFC/DISM)'
    Write-Host '     6 - Quan ly quyen so huu'
    Write-Host '     7 - Quan ly Windows Update'
    Write-Host '     8 - Xoa cache card man hinh'
    Write-Host '     9 - Toi uu ung dung CAD/Office'
    Write-Host '     A - Cai dat phan mem & Driver'
    Write-Host '     B - Huong dan nang cao'
    Write-Host '     C - Tao diem khoi phuc he thong [MOI]'
    Write-Host '     D - Quan ly ung dung khoi dong [MOI]'
    Write-Host '     E - Kiem tra suc khoe o cung [MOI]'
    Write-Host '     0 - Thoat chuong trinh'
    Write-Host ''
    Write-Host '    ================================================'
    Write-Host ''
    $choice = (Read-Host 'Moi chon [0-9,A-E]').Trim().ToUpper()
    switch ($choice) {
        '1' { Clean-TempGroup }
        '2' { Clean-WUpdate }
        '3' { Clean-Browsers }
        '4' { Run-DiskCleanup }
        '5' { Run-SystemRepair }
        '6' { Run-TakeOwnership }
        '7' { Manage-WinUpdate }
        '8' { Clean-GpuCache }
        '9' { Manage-AppOptimization }
        'A' { Manage-SoftwareInstall }
        'B' { Show-GpuGuide }
        'C' { New-RestorePoint }
        'D' { Open-StartupManager }
        'E' { Manage-DiskHealth }
        '0' { break }
        default { Write-Host 'Lua chon khong hop le.'; Start-Sleep -Seconds 1 }
    }
    if ($choice -eq '0') { break }
}
Write-Host 'Tam biet.'
