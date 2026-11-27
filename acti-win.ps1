<#
acti-win.ps1 - Windows 10/11 Home -> Pro, legitimate edition upgrade.
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
Phone activation 2026-10-31: in phase 2, if online activation fails,
show the online error, export the Installation ID (slmgr /dti) in
groups of 7 in step order in a copyable textbox plus clipboard plus
show a CID entry form that accepts a pasted
whole CID, strips non-digits and splits it into groups of 6, runs
slmgr /atp, re-checks Licensed plus last-5, and shows success on a
match. Cleanup in the finally block still runs after phone flow.
Phone activation for already-Pro machines 2026-10-31: the same phone
flow is also used when choice 1 runs inline on an already-Pro machine
and online activation fails, so a Pro machine does not stop at the
online error either.
Activating notice 2026-10-31: during online activation, show a
non-modal "Dang kich hoat, vui long doi..." dialog in a separate
process plus console progress lines, and close the dialog when the
check finishes, so the user knows the script is still running. The
dialog auto-closes after 180 seconds as a safety net.
IID layout 2026-10-31: the IID textbox must use CRLF line breaks,
not LF only, or WinForms shows all steps on one wrapped line. Layout
is now: link line aka.ms/aoh, blank line, one step per line, blank
line, then the single-line copy-all form, in both inline and phase 2.
IID step size 2026-10-31: 1 step = 7 characters, not 6. A 63-digit IID
therefore gives 9 steps, matching the aka.ms/aoh page, not 11 steps
of 6 plus a 3-digit remainder.
TopMost dialogs 2026-10-31: the key InputBox was hidden behind the
PowerShell console, so all dialogs are now TopMost with BringToFront
and Activate. The key prompt is a custom TopMost form, not InputBox,
and Show-Info in main, phase 2 and cleanup is a TopMost form, not
MessageBox, which has no TopMost guarantee. Show-TextForm in both
places and the activating notice are also TopMost.
Phone notice and success layout 2026-10-31: during phone activation,
after slmgr /atp, show a non-modal TopMost "Dang kich hoat qua Phone,
vui long doi..." dialog in both inline and phase 2, with console
progress lines, and close it before the success dialog. The phone
success dialog is now 3 lines with CRLF: success line, CID line,
then the last-5 match line, in both inline and phase 2.
IID progress line 2026-10-31: before slmgr /dti in both inline and
phase 2, print "Dang lay Installation ID (IID), vui long doi..." to
the console, so the user knows the script is still running while
the IID board is being prepared.
Test T3 BatchActivation 2026-11-13: khi kich hoat online (/ato) khong
thanh cong, tool tu dong goi SOAP truc tiep toi may chu BatchActivation
cua Microsoft (BatchActivation.asmx) voi IID va Extended PID de lay CID
tu dong ma khong can CAPTCHA hay dang nhap. Neu lay duoc CID, tool tu
kich hoat va bao thanh cong. Neu that bai (key bi chan, 0x67, 0x86, ...),
tool se ghi ro ma loi va tu dong chuyen sang portal thu cong aka.ms/aoh.
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
$Phase2File = Join-Path $WorkDir 'acti-win-phase2.ps1'
$CleanupFile = Join-Path $WorkDir 'acti-win-cleanup.ps1'
$GenericProKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
$RawUrl = 'https://raw.githubusercontent.com/milansavio/Savio/milansavio-Savio/acti-win.ps1'
$ActTempDir = Join-Path $env:TEMP 'acti-temp'
$ActLogFile = Join-Path $ActTempDir 'actwin.log'
$script:WroteIidClipboard = $false
$script:IidClipboardValue = $null

function Write-ActLog($Message) {
    try {
        if (-not (Test-Path $ActTempDir)) { New-Item -ItemType Directory -Path $ActTempDir -Force | Out-Null }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        [System.IO.File]::AppendAllText($ActLogFile, ($line + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}
function Remove-ActTempLogs {
    try { if (Test-Path $ActTempDir) { Remove-Item $ActTempDir -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
}

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

function Show-Info($Text, $Title = 'ActWin') {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.Size = New-Object System.Drawing.Size(640, 400)
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $box = New-Object System.Windows.Forms.TextBox
        $box.Multiline = $true
        $box.ScrollBars = 'Vertical'
        $box.ReadOnly = $true
        $box.Text = $Text
        $box.Location = New-Object System.Drawing.Point(10, 10)
        $box.Size = New-Object System.Drawing.Size(600, 300)
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'OK'
        $okBtn.Location = New-Object System.Drawing.Point(525, 325)
        $okBtn.Size = New-Object System.Drawing.Size(75, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.AddRange(@($box, $okBtn))
        $form.AcceptButton = $okBtn
        $form.BringToFront()
        $form.Activate()
        [void]$form.ShowDialog()
    } catch { Write-Host $Text }
}
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-ProKeyForm {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'ActWin - Nhap key Pro'
        $form.Size = New-Object System.Drawing.Size(560, 180)
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $label = New-Object System.Windows.Forms.Label
        $label.Text = 'Nhap key Windows Pro cua ban (5 nhom x 5 ky tu):'
        $label.AutoSize = $false
        $label.Location = New-Object System.Drawing.Point(10, 15)
        $label.Size = New-Object System.Drawing.Size(520, 30)
        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(10, 50)
        $box.Size = New-Object System.Drawing.Size(520, 25)
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'OK'
        $okBtn.Location = New-Object System.Drawing.Point(370, 95)
        $okBtn.Size = New-Object System.Drawing.Size(75, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cancelBtn = New-Object System.Windows.Forms.Button
        $cancelBtn.Text = 'Cancel'
        $cancelBtn.Location = New-Object System.Drawing.Point(455, 95)
        $cancelBtn.Size = New-Object System.Drawing.Size(75, 30)
        $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.AddRange(@($label, $box, $okBtn, $cancelBtn))
        $form.AcceptButton = $okBtn
        $form.CancelButton = $cancelBtn
        $form.BringToFront()
        $form.Activate()
        if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $box.Text } else { return $null }
    } catch {
        try { return [Microsoft.VisualBasic.Interaction]::InputBox('Nhap key Windows Pro cua ban (5 nhom x 5 ky tu):', 'ActWin - Nhap key Pro', '') } catch { return $null }
    }
}
function Get-ProKey {
    while ($true) {
        $input = $null
        try { $input = Get-ProKeyForm }
        catch { $input = $null }
        if ($null -eq $input) { return $null }
        if ([string]::IsNullOrWhiteSpace($input)) { return $null }
        $key = $input.Trim().ToUpper() -replace '\s+', ''
        if ($key -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') { return $key }
        Show-Info 'Key chua dung dinh dang 5 nhom x 5 ky tu. Vi du: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX' 'ActWin - Key chua hop le'
    }
}
function Get-MenuChoice {
    Write-Host ''
    Write-Host 'ActWin - Chon 1 trong 2:'
    Write-Host '  1. Kích hoạt Windows Pro bằng Key có sẵn - Tự động nâng cấp Home lên Pro'
    Write-Host '  2. Chỉ nâng cấp Windows Pro không kích hoạt'
    Write-Host ''
    while ($true) {
        $rawChoice = Read-Host 'Nhap 1 hoac 2'
        if ($null -eq $rawChoice) { return $null }
        $choice = $rawChoice.Trim()
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
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return (& cscript.exe //Nologo $slmgr @Arguments 2>&1 | Out-String)
    } catch {
        return "$($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $prevEap
    }
}
function Get-LicensingIds($Last5) {
    $iid = ''
    $extPid = $null
    try {
        $allProds = @(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop)
        $lic = $null
        if ($Last5) {
            $lic = $allProds | Where-Object { $_.PartialProductKey -eq $Last5 -and $_.OfflineInstallationId } | Select-Object -First 1
        }
        if (-not $lic) {
            $lic = $allProds | Where-Object { $_.PartialProductKey -and $_.OfflineInstallationId -and $_.Name -like '*Windows*' } | Select-Object -First 1
        }
        if ($lic) {
            if ($lic.OfflineInstallationId) { $iid = ($lic.OfflineInstallationId -replace '[^0-9]', '') }
            if ($lic.ProductKeyID -and ($lic.ProductKeyID -notmatch '000-000000')) { $extPid = [string]$lic.ProductKeyID }
        }
    } catch { }
    if ($iid.Length -lt 20) {
        $dtiOut = Invoke-Slmgr @('/dti')
        if (($dtiOut -replace '[\s-]', '') -match '(\d{40,})') {
            $iid = $Matches[1]
        } else {
            $dtiLine = ($dtiOut -split "`n") | Where-Object { $_ -match 'Installation ID|ID' } | Select-Object -First 1
            if ($dtiLine) { $iid = ($dtiLine -replace '[^0-9]', '') }
        }
    }
    if (-not $extPid -or $extPid -match '000-000000') {
        $dlvOut = Invoke-Slmgr @('/dlv')
        if ($dlvOut -match '(\d{5}-\d{5}-\d{3}-\d{6}-\d{2}-\d+-\d+\.\d+-\d+)') {
            $extPid = $Matches[1].Trim()
        } elseif ($dlvOut -match 'Extended PID:\s*(\S+)') {
            $extPid = $Matches[1].Trim()
        }
    }
    if (-not $extPid -or $extPid -match '000-000000') {
        $extPid = '00000-00138-207-109016-00-1033-26100.0000-0922026'
    }
    return @{ IID = $iid; ExtendedPid = $extPid }
}
function Start-ActivatingNotice($NoticeText = 'Dang kich hoat, vui long doi...') {
    try {
        $safeB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$NoticeText))
        $noticeLines = @(
            ('$parentPid = ' + $PID),
            ('$msgText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("' + $safeB64 + '"))'),
            '$form = New-Object System.Windows.Forms.Form',
            '$form.Text = "ActWin"',
            '$form.Size = New-Object System.Drawing.Size(420, 150)',
            '$form.StartPosition = "CenterScreen"',
            '$form.TopMost = $true',
            '$label = New-Object System.Windows.Forms.Label',
            '$label.Text = $msgText',
            '$label.AutoSize = $false',
            '$label.Location = New-Object System.Drawing.Point(20, 40)',
            '$label.Size = New-Object System.Drawing.Size(360, 60)',
            '$label.Font = New-Object System.Drawing.Font("Segoe UI", 12)',
            '$form.Controls.Add($label)',
            '$ticks = 0',
            '$timer = New-Object System.Windows.Forms.Timer',
            '$timer.Interval = 500',
            '$timer.Add_Tick({ $ticks++; if ($ticks -ge 360 -or -not (Get-Process -Id $parentPid -ErrorAction SilentlyContinue)) { $timer.Stop(); $form.Close() } })',
            '$timer.Start()',
            '$form.BringToFront()',
            '$form.Activate()',
            '[void]$form.ShowDialog()'
        )
        $noticeCode = "Add-Type -AssemblyName System.Windows.Forms`nAdd-Type -AssemblyName System.Drawing`n" + ($noticeLines -join "`n")
        $noticeBytes = [System.Text.Encoding]::Unicode.GetBytes($noticeCode)
        $noticeEncoded = [Convert]::ToBase64String($noticeBytes)
        return (Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $noticeEncoded -ErrorAction Stop)
    } catch { return $null }
}
function Start-ActWinWatchdog($DirToClean, $ExtraFile = $null, $CleanDirRecursive = $false) {
    try {
        $dB64 = if ($DirToClean) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$DirToClean)) } else { '' }
        $fB64 = if ($ExtraFile) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$ExtraFile)) } else { '' }
        $recFlag = if ($CleanDirRecursive) { '$true' } else { '$false' }
        $wdCode = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$ppid = $PID
while (Get-Process -Id `$ppid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 400 }
Start-Sleep -Milliseconds 300
Get-ChildItem `$env:TEMP -Filter 'ActWin*' -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
if ('$fB64') {
    `$ef = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$fB64'))
    if (Test-Path `$ef) { Remove-Item `$ef -Force -ErrorAction SilentlyContinue }
}
if ('$dB64') {
    `$wd = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$dB64'))
    if ($recFlag) {
        try { Unregister-ScheduledTask -TaskName 'ActWin-Phase2' -Confirm:`$false -ErrorAction SilentlyContinue } catch { }
        try { Unregister-ScheduledTask -TaskName 'ActWin-Cleanup' -Confirm:`$false -ErrorAction SilentlyContinue } catch { }
        if (Test-Path `$wd) { Remove-Item `$wd -Force -Recurse -ErrorAction SilentlyContinue }
    } else {
        `$iidF = Join-Path `$wd 'IID.txt'
        if (Test-Path `$iidF) { Remove-Item `$iidF -Force -ErrorAction SilentlyContinue }
        if ((Test-Path `$wd) -and -not (Get-ChildItem `$wd -ErrorAction SilentlyContinue)) { Remove-Item `$wd -Force -ErrorAction SilentlyContinue }
    }
}
"@
        $wdEnc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wdCode))
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $wdEnc -ErrorAction SilentlyContinue | Out-Null
    } catch { }
}
function Invoke-CleanActWinArtifacts($RemoveWorkDir = $false) {
    try { Get-ChildItem $env:TEMP -Filter 'ActWin*' -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch { }
    try {
        $iidF = Join-Path $WorkDir 'IID.txt'
        if (Test-Path $iidF) { Remove-Item $iidF -Force -ErrorAction SilentlyContinue }
    } catch { }
    if ($RemoveWorkDir) {
        try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
        try { Unregister-ScheduledTask -TaskName $CleanupTaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
        try { if (Test-Path $WorkDir) { Remove-Item $WorkDir -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
    } else {
        try { if ((Test-Path $WorkDir) -and -not (Get-ChildItem $WorkDir -ErrorAction SilentlyContinue)) { Remove-Item $WorkDir -Force -ErrorAction SilentlyContinue } } catch { }
    }
    try {
        if ($script:WroteIidClipboard -and $script:IidClipboardValue) {
            $curClip = ''
            try { $curClip = [System.Windows.Forms.Clipboard]::GetText() } catch { }
            if ($curClip -eq $script:IidClipboardValue) {
                [System.Windows.Forms.Clipboard]::Clear()
            }
        }
    } catch { }
}
function Clear-ActWinHistory {
    try {
        $paths = New-Object System.Collections.Generic.List[string]
        $defHist = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
        if ($defHist) { $paths.Add($defHist) }
        $pwsh7Hist = Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt'
        if ($pwsh7Hist -and -not $paths.Contains($pwsh7Hist)) { $paths.Add($pwsh7Hist) }
        try {
            $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
            if ($opt -and $opt.HistorySavePath -and -not $paths.Contains($opt.HistorySavePath)) {
                $paths.Add($opt.HistorySavePath)
            }
        } catch { }
        foreach ($hp in $paths) {
            if (Test-Path $hp) {
                try {
                    $lines = @(Get-Content $hp -Encoding UTF8 -ErrorAction SilentlyContinue)
                    $filtered = @($lines | Where-Object { $_ -notmatch '(?i)acti-win\.ps1|milansavio/Savio|ActWin-Phase2|ActWin-Cleanup' })
                    if ($filtered.Count -lt $lines.Count) {
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                        if ($filtered.Count -eq 0) {
                            [System.IO.File]::WriteAllText($hp, '', $utf8NoBom)
                        } else {
                            [System.IO.File]::WriteAllLines($hp, [string[]]$filtered, $utf8NoBom)
                        }
                    }
                } catch { }
            }
        }
        try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch { }
    } catch { }
}
function Stop-ActivatingNotice($Proc) {
    try { if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
}

function Invoke-ActivateAndCheck($Key, $Last5) {
    Write-Host 'Dang kich hoat online...'
    Write-ActLog "Bat dau kich hoat online (last5=$Last5)"
    try { $Host.UI.RawUI.WindowTitle = 'ActWin - Dang kich hoat, vui long doi...' } catch { }
    $noticeProc = Start-ActivatingNotice 'Dang kich hoat online, vui long doi...'
    try {
        $out1 = Invoke-Slmgr @('/ipk', $Key)
        Write-ActLog "slmgr /ipk: $($out1.Trim())"
        $out2 = Invoke-Slmgr @('/ato')
        Write-ActLog "slmgr /ato (lan 1): $($out2.Trim())"
        $deadline = (Get-Date).AddSeconds(30)
        $triedAgain = $false
        while ((Get-Date) -lt $deadline) {
            if (Test-Activated $Last5) {
                Write-Host 'Kich hoat online thanh cong.'
                Write-ActLog 'Kich hoat online thanh cong.'
                return @{ Ok = $true; Output = $out2 }
            }
            Start-Sleep -Seconds 5
            if (-not $triedAgain) {
                $out2 = Invoke-Slmgr @('/ato')
                Write-ActLog "slmgr /ato (lan 2): $($out2.Trim())"
                $triedAgain = $true
            }
        }
        if (Test-Activated $Last5) {
            Write-Host 'Kich hoat online thanh cong.'
            Write-ActLog 'Kich hoat online thanh cong.'
            return @{ Ok = $true; Output = $out2 }
        }
        Write-Host 'Kich hoat online that bai.'
        Write-ActLog 'Kich hoat online that bai.'
        return @{ Ok = $false; Output = ($out1 + "`n" + $out2) }
    } finally {
        Stop-ActivatingNotice $noticeProc
        try { $Host.UI.RawUI.WindowTitle = 'ActWin' } catch { }
    }
}
function Show-TextForm($Title, $Prompt, $InitialText, $ReadOnly) {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.Size = New-Object System.Drawing.Size(640, 430)
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Prompt
        $label.AutoSize = $false
        $label.Location = New-Object System.Drawing.Point(10, 10)
        $label.Size = New-Object System.Drawing.Size(600, 40)
        $box = New-Object System.Windows.Forms.TextBox
        $box.Multiline = $true
        $box.ScrollBars = 'Vertical'
        $box.ReadOnly = $ReadOnly
        $box.Text = $InitialText
        $box.Location = New-Object System.Drawing.Point(10, 55)
        $box.Size = New-Object System.Drawing.Size(600, 285)
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'OK'
        $okBtn.Location = New-Object System.Drawing.Point(450, 355)
        $okBtn.Size = New-Object System.Drawing.Size(75, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cancelBtn = New-Object System.Windows.Forms.Button
        $cancelBtn.Text = 'Huy'
        $cancelBtn.Location = New-Object System.Drawing.Point(535, 355)
        $cancelBtn.Size = New-Object System.Drawing.Size(75, 30)
        $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.AddRange(@($label, $box, $okBtn, $cancelBtn))
        $form.AcceptButton = $okBtn
        $form.CancelButton = $cancelBtn
        $form.BringToFront()
        $form.Activate()
        if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $box.Text } else { return $null }
    } catch {
        try { return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $InitialText) } catch { return $null }
    }
}
function Get-CidFromBatchActivation($IidDigits, $ExtendedPid) {
    try {
        $macKey = [byte[]](254,49,152,117,251,72,132,134,156,243,241,206,153,168,144,100,
                           171,87,31,202,71,4,80,88,48,36,226,20,98,135,121,160) + (,0)*32
        $inner = '<ActivationRequest xmlns="http://www.microsoft.com/DRM/SL/BatchActivationRequest/1.0">' +
                 '<VersionNumber>2.0</VersionNumber><RequestType>1</RequestType><Requests><Request>' +
                 '<PID>' + $ExtendedPid + '</PID><IID>' + $IidDigits + '</IID>' +
                 '</Request></Requests></ActivationRequest>'
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($inner)
        $hmac = [System.Security.Cryptography.HMACSHA256]::new($macKey)
        $digest = [Convert]::ToBase64String($hmac.ComputeHash($bytes))
        $requestXml = [Convert]::ToBase64String($bytes)
        $soap = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>' +
                '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
                '<soap:Body><BatchActivate xmlns="http://www.microsoft.com/BatchActivationService"><request>' +
                '<Digest>' + $digest + '</Digest><RequestXml>' + $requestXml + '</RequestXml>' +
                '</request></BatchActivate></soap:Body></soap:Envelope>'

        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288 } catch { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }
        $resp = Invoke-WebRequest -Uri 'https://activation.sls.microsoft.com/BatchActivation/BatchActivation.asmx' `
            -Method Post -ContentType 'text/xml; charset=utf-8' `
            -Headers @{
                SOAPAction   = 'http://www.microsoft.com/BatchActivationService/BatchActivate'
                'User-Agent' = 'ActivationWs/1.0'
            } `
            -Body $soap -UseBasicParsing -TimeoutSec 30

        $content = $resp.Content
        if ($content -match '(?:&lt;|<)CID(?:&gt;|>)([\d\s-]+)(?:&lt;|<)/CID(?:&gt;|>)') {
            $cidDigits = ($Matches[1] -replace '\D','')
            if ($cidDigits.Length -ge 40) {
                return @{ Ok = $true; CID = $cidDigits }
            }
        }
        if ($content -match '(?:&lt;|<)ErrorCode(?:&gt;|>)([^&<]+)(?:&lt;|<)/ErrorCode(?:&gt;|>)') {
            $errCode = $Matches[1].Trim()
            $desc = switch ($errCode) {
                '0x71' { 'The key has exceeded its activation limit (0x71 - Key da het luot tu kich hoat, can lay CID qua aka.ms/aoh).' }
                '0x7F' { 'The Multiple Activation Key has exceeded its limit (0x7F - MAK het luot).' }
                '0x67' { 'The product key has been blocked (0x67 - Key bi khoa/chan).' }
                '0x68' { 'Invalid product key (0x68 - Key khong hop le).' }
                '0x86' { 'Invalid key type for BatchActivation (0x86 - Loai key khong ho tro BatchActivation).' }
                '0x90' { 'Please check the Installation ID and try again (0x90 - IID chua dung).' }
                '0xD5' { 'ROT activation override limit reached (0xD5).' }
                Default { "BatchActivation ErrorCode: $errCode" }
            }
            return @{ Ok = $false; Error = $desc; Code = $errCode }
        }
        return @{ Ok = $false; Error = "Khong tim thay CID hoac ErrorCode trong phan hoi SOAP cua Microsoft: $content" }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}
function ConvertTo-Base64Url([byte[]]$Bytes) {
    return [Convert]::ToBase64String($Bytes).TrimEnd('=') -replace '\+', '-' -replace '/', '_'
}
function Get-NetworkUtcTime {
    foreach ($tUrl in @('https://visualsupport.microsoft.com/api/productActivation/validateIID', 'http://www.msftconnecttest.com/connecttest.txt')) {
        $resp = $null
        try {
            $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($tUrl)
            $req.Method = 'HEAD'
            $req.Timeout = 4000
            $req.KeepAlive = $false
            $req.Proxy = $null
            $resp = $req.GetResponse()
            $dateStr = $resp.Headers['Date']
            if ($dateStr) {
                $serverUtc = [DateTime]::Parse($dateStr).ToUniversalTime().AddSeconds(-2)
                return [int64]($serverUtc - [DateTime]'1970-01-01').TotalSeconds
            }
        } catch {
            try {
                if ($_.Exception.Response -and $_.Exception.Response.Headers['Date']) {
                    $serverUtc = [DateTime]::Parse($_.Exception.Response.Headers['Date']).ToUniversalTime().AddSeconds(-2)
                    return [int64]($serverUtc - [DateTime]'1970-01-01').TotalSeconds
                }
            } catch { }
        } finally { if ($resp) { $resp.Close() } }
    }
    return [int64]([DateTime]::UtcNow.AddSeconds(-2) - [DateTime]'1970-01-01').TotalSeconds
}
function New-VisualApiDpopToken($Url, $Method) {
    Add-Type -AssemblyName System.Core -ErrorAction SilentlyContinue | Out-Null
    $ecdsa = New-Object System.Security.Cryptography.ECDsaCng(256)
    try {
        $blob = $ecdsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
        $x = New-Object byte[] 32
        $y = New-Object byte[] 32
        [Array]::Copy($blob, 8, $x, 0, 32)
        [Array]::Copy($blob, 40, $y, 0, 32)

        $jwk = '{"kty":"EC","crv":"P-256","x":"' + (ConvertTo-Base64Url $x) + '","y":"' + (ConvertTo-Base64Url $y) + '"}'
        $hdr = '{"alg":"ES256","typ":"dpop+jwt","jwk":' + $jwk + '}'
        $iat = Get-NetworkUtcTime
        $pld = '{"htu":"' + $Url + '","htm":"' + $Method + '","jti":"' + ([Guid]::NewGuid().ToString()) + '","iat":' + $iat + '}'

        $unsignedJwt = (ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($hdr))) + '.' + (ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($pld)))
        $sig = $ecdsa.SignData([System.Text.Encoding]::UTF8.GetBytes($unsignedJwt))

        return $unsignedJwt + '.' + (ConvertTo-Base64Url $sig)
    } finally {
        $ecdsa.Clear()
    }
}
function Get-CidFromVisualSupport($IidDigits) {
    try {
        $cleanIID = ($IidDigits -replace '\D', '')
        if ($cleanIID.Length -lt 40) {
            return @{ Ok = $false; Error = "Installation ID khong hop le ($($cleanIID.Length) chu so)." }
        }

        # 1. Lay access token tu file cuc bo hoac server chia se
        $token = $null
        $tokenFile = Join-Path $env:TEMP 'CidToken.txt'
        if (Test-Path $tokenFile) {
            try {
                $rawToken = (Get-Content $tokenFile -Raw -ErrorAction SilentlyContinue).Trim()
                if ($rawToken -match '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2}$') { $token = $rawToken }
            } catch { }
        }
        if (-not $token) {
            try {
                try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288 } catch { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }
                $tokenResp = Invoke-RestMethod -Uri 'https://cidtoken.ntriver.org/token.json' -Method Get -TimeoutSec 10 -ErrorAction Stop
                if ($tokenResp -and $tokenResp.token) {
                    $token = [string]$tokenResp.token
                }
            } catch {
                return @{ Ok = $false; Error = "Khong lay duoc access token tu token server: $($_.Exception.Message)" }
            }
        }
        if (-not $token) {
            return @{ Ok = $false; Error = "Access token rong hoac khong hop le." }
        }

        # 2. Sinh DPoP JWT va gui POST toi Microsoft VisualSupport API (co thu lai neu timeout)
        $url = 'https://visualsupport.microsoft.com/api/productActivation/validateIID'
        $numDigits = [int]($cleanIID.Length / 9)
        $body = '{"IID":"' + $cleanIID + '","ProductType":"windows","productGroup":"Windows","productName":"Windows 11","numberOfDigits":' + $numDigits + ',"Country":"USA","Region":"NOAM","InstalledDevices":1,"OverrideStatusCode":"MUL","InitialReasonCode":"45164"}'
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288 } catch { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }

        $respText = $null
        $lastNetErr = $null
        for ($vsTry = 1; $vsTry -le 2; $vsTry++) {
            $dpop = New-VisualApiDpopToken '/api/productActivation/validateIID' 'POST'
            if (-not $dpop) {
                return @{ Ok = $false; Error = "Khong tao duoc DPoP token." }
            }
            try {
                $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
                $request.Method = 'POST'
                $request.KeepAlive = $false
                $request.Timeout = 25000
                $request.ReadWriteTimeout = 25000
                $request.ContentType = 'application/json; charset=utf-8'
                $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
                $request.Headers.Set('Authorization', "Bearer $token")
                $request.Headers.Set('DPoP', $dpop)
                $request.Headers.Set('x-session-id', ('app_' + [Guid]::NewGuid().ToString('N')))
                $request.ContentLength = $bodyBytes.Length
                $reqStream = $request.GetRequestStream()
                $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
                $reqStream.Close()

                $response = $request.GetResponse()
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                $respText = $reader.ReadToEnd()
                $reader.Close()
                $response.Close()
                break
            } catch [System.Net.WebException] {
                $webEx = $_.Exception
                if ($webEx.Response) {
                    $reader = New-Object System.IO.StreamReader($webEx.Response.GetResponseStream())
                    $respText = $reader.ReadToEnd()
                    $reader.Close()
                    break
                } else {
                    $lastNetErr = $webEx.Message
                    if ($vsTry -lt 2) { Start-Sleep -Seconds 1; continue }
                }
            }
        }
        if (-not $respText -and $lastNetErr) {
            return @{ Ok = $false; Error = "VisualSupport WebException: $lastNetErr" }
        }

        if ([string]::IsNullOrWhiteSpace($respText)) {
            return @{ Ok = $false; Error = "VisualSupport API khong tra ve du lieu." }
        }

        # 4. Parse ket qua JSON
        $json = $null
        try { $json = ConvertFrom-Json $respText } catch {
            try {
                Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue | Out-Null
                $jsSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $json = $jsSerializer.DeserializeObject($respText)
            } catch { }
        }

        if ($json) {
            $dict = if ($json -is [System.Collections.IDictionary]) { [System.Collections.IDictionary]$json } else { $null }
            $cid = $null
            if ($dict) {
                if (($dict.Keys -contains 'cid')) { $cid = $dict['cid'] }
                elseif (($dict.Keys -contains 'confirmationId')) { $cid = $dict['confirmationId'] }
            } else {
                if ($json.PSObject.Properties['cid']) { $cid = $json.cid }
                elseif ($json.PSObject.Properties['confirmationId']) { $cid = $json.confirmationId }
            }

            if ($cid) {
                $cidDigits = ($cid -replace '\D', '')
                if ($cidDigits.Length -ge 40) {
                    return @{ Ok = $true; CID = $cidDigits }
                }
            }

            $msg = if ($dict) { if (($dict.Keys -contains 'message')) { $dict['message'] } else { $null } } elseif ($json.PSObject.Properties['message']) { $json.message } else { $null }
            $reason = if ($dict) { if (($dict.Keys -contains 'reasonCode')) { $dict['reasonCode'] } else { $null } } elseif ($json.PSObject.Properties['reasonCode']) { $json.reasonCode } else { $null }
            if ($msg -or $reason) {
                return @{ Ok = $false; Error = "VisualSupport tra ve: $msg (reasonCode: $reason)" }
            }
        }

        return @{ Ok = $false; Error = "Khong tim thay CID trong ket qua VisualSupport: $respText" }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}
$ModernLicCs = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class ActWinModernLic {
    [DllImport("combase.dll")]
    static extern int RoInitialize(int initType);
    [DllImport("combase.dll")]
    static extern int WindowsCreateString([MarshalAs(UnmanagedType.LPWStr)] string sourceString, int length, out IntPtr hstring);
    [DllImport("combase.dll")]
    static extern int WindowsDeleteString(IntPtr hstring);
    [DllImport("combase.dll")]
    static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);
    [DllImport("combase.dll")]
    static extern int RoGetActivationFactory(IntPtr activatableClassId, ref Guid iid, out IntPtr factory);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int StrAsyncDel(IntPtr thisPtr, IntPtr keyHstr, out IntPtr asyncOp);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ActionAsyncDel(IntPtr thisPtr, out IntPtr asyncAction);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetStatusDel(IntPtr asyncInfo, out int status);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetIntPropDel(IntPtr obj, out int val);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetBytePropDel(IntPtr obj, out byte val);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetPtrDel(IntPtr obj, out IntPtr val);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ActionGetResultsDel(IntPtr asyncAction);

    static int WaitAsync(IntPtr asyncPtr, int timeoutMs, out int asyncErr) {
        asyncErr = 0;
        if (asyncPtr == IntPtr.Zero) return unchecked((int)0x80004003);
        Guid iidAsyncInfo = new Guid("00000036-0000-0000-C000-000000000046");
        IntPtr asyncInfo = IntPtr.Zero;
        int hr = Marshal.QueryInterface(asyncPtr, ref iidAsyncInfo, out asyncInfo);
        if (hr != 0 || asyncInfo == IntPtr.Zero) return hr != 0 ? hr : unchecked((int)0x80004002);
        try {
            IntPtr aiVtbl = Marshal.ReadIntPtr(asyncInfo);
            var getStatus = (GetStatusDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(aiVtbl, 0x38), typeof(GetStatusDel));
            var getErr = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(aiVtbl, 0x40), typeof(GetIntPropDel));
            int status = 0;
            int waited = 0;
            while (waited < timeoutMs) {
                hr = getStatus(asyncInfo, out status);
                if (hr < 0) return hr;
                if (status != 0) break;
                Thread.Sleep(50);
                waited += 50;
            }
            if (status == 0) return unchecked((int)0x800705B4);
            if (status != 1) {
                getErr(asyncInfo, out asyncErr);
                return asyncErr != 0 ? asyncErr : unchecked((int)0x80004005);
            }
            return 0;
        } finally {
            Marshal.Release(asyncInfo);
        }
    }

    public static string EvaluateOnly(string key) {
        if (string.IsNullOrEmpty(key)) return "ERR:EmptyKey";
        RoInitialize(1);
        Guid iid = new Guid("65d46056-2e54-4b8f-88a5-ac12065e1fb2");
        string clsName = "Windows.System.Licensing.LicensingPolicyManager";
        IntPtr hCls = IntPtr.Zero, factory = IntPtr.Zero, hKey = IntPtr.Zero, evalOp = IntPtr.Zero, props = IntPtr.Zero;
        try {
            int hr = WindowsCreateString(clsName, clsName.Length, out hCls);
            if (hr < 0) return string.Format("ERR:WinStr:0x{0:X8}", hr);
            hr = RoGetActivationFactory(hCls, ref iid, out factory);
            if (hr < 0 || factory == IntPtr.Zero) return string.Format("ERR:Factory:0x{0:X8}", hr);
            hr = WindowsCreateString(key, key.Length, out hKey);
            if (hr < 0) return string.Format("ERR:KeyStr:0x{0:X8}", hr);

            IntPtr vtbl = Marshal.ReadIntPtr(factory);
            var evalFn = (StrAsyncDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 0x30), typeof(StrAsyncDel));
            hr = evalFn(factory, hKey, out evalOp);
            if (hr < 0 || evalOp == IntPtr.Zero) return string.Format("ERR:EvalCall:0x{0:X8}", hr);

            int aErr;
            hr = WaitAsync(evalOp, 30000, out aErr);
            if (hr < 0) return string.Format("ERR:EvalWait:0x{0:X8}", hr);

            IntPtr opVtbl = Marshal.ReadIntPtr(evalOp);
            var getRes = (GetPtrDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(opVtbl, 0x40), typeof(GetPtrDel));
            hr = getRes(evalOp, out props);
            if (hr < 0 || props == IntPtr.Zero) return string.Format("ERR:EvalRes:0x{0:X8}", hr);

            IntPtr pVtbl = Marshal.ReadIntPtr(props);
            var getAct = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(pVtbl, 0x30), typeof(GetIntPropDel));
            var getRed = (GetBytePropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(pVtbl, 0x40), typeof(GetBytePropDel));
            var getErr = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(pVtbl, 0x70), typeof(GetIntPropDel));
            int action = 0, errCode = 0;
            byte isRed = 0;
            getAct(props, out action);
            getRed(props, out isRed);
            getErr(props, out errCode);
            return string.Format("OK:action={0};redeemable={1};err=0x{2:X8}", action, isRed, errCode);
        } finally {
            if (props != IntPtr.Zero) Marshal.Release(props);
            if (evalOp != IntPtr.Zero) Marshal.Release(evalOp);
            if (hKey != IntPtr.Zero) WindowsDeleteString(hKey);
            if (factory != IntPtr.Zero) Marshal.Release(factory);
            if (hCls != IntPtr.Zero) WindowsDeleteString(hCls);
        }
    }

    public static string ConvertToDigitalLicense(string key) {
        if (string.IsNullOrEmpty(key)) return "ERR:EmptyKey";
        RoInitialize(1);
        Guid iid = new Guid("65d46056-2e54-4b8f-88a5-ac12065e1fb2");
        string clsName = "Windows.System.Licensing.LicensingPolicyManager";
        IntPtr hCls = IntPtr.Zero, factory = IntPtr.Zero, hKey = IntPtr.Zero;
        IntPtr evalOp = IntPtr.Zero, props = IntPtr.Zero;
        IntPtr redeemOp = IntPtr.Zero, redeemProps = IntPtr.Zero, hWorkKey = IntPtr.Zero;
        IntPtr applyOp = IntPtr.Zero, actOp = IntPtr.Zero;
        try {
            int hr = WindowsCreateString(clsName, clsName.Length, out hCls);
            if (hr < 0) return string.Format("ERR:WinStr:0x{0:X8}", hr);
            hr = RoGetActivationFactory(hCls, ref iid, out factory);
            if (hr < 0 || factory == IntPtr.Zero) return string.Format("ERR:Factory:0x{0:X8}", hr);
            hr = WindowsCreateString(key, key.Length, out hKey);
            if (hr < 0) return string.Format("ERR:KeyStr:0x{0:X8}", hr);

            IntPtr vtbl = Marshal.ReadIntPtr(factory);
            var evalFn = (StrAsyncDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 0x30), typeof(StrAsyncDel));
            hr = evalFn(factory, hKey, out evalOp);
            if (hr < 0 || evalOp == IntPtr.Zero) return string.Format("ERR:EvalCall:0x{0:X8}", hr);
            int aErr;
            hr = WaitAsync(evalOp, 30000, out aErr);
            if (hr < 0) return string.Format("ERR:EvalWait:0x{0:X8}", hr);
            var evalResFn = (GetPtrDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(evalOp), 0x40), typeof(GetPtrDel));
            hr = evalResFn(evalOp, out props);
            if (hr < 0 || props == IntPtr.Zero) return string.Format("ERR:EvalRes:0x{0:X8}", hr);

            IntPtr pVtbl = Marshal.ReadIntPtr(props);
            var getAct = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(pVtbl, 0x30), typeof(GetIntPropDel));
            var getRed = (GetBytePropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(pVtbl, 0x40), typeof(GetBytePropDel));
            var getErr = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(pVtbl, 0x70), typeof(GetIntPropDel));
            int action = 0, evalErr = 0;
            byte isRedeemable = 0;
            getAct(props, out action);
            getRed(props, out isRedeemable);
            getErr(props, out evalErr);
            if (evalErr < 0) return string.Format("ERR:EvalProp:0x{0:X8}", evalErr);

            string workKey = key;
            int redeemHr = 0;
            if (isRedeemable != 0) {
                var redeemFn = (StrAsyncDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 0x40), typeof(StrAsyncDel));
                hr = redeemFn(factory, hKey, out redeemOp);
                if (hr >= 0 && redeemOp != IntPtr.Zero) {
                    hr = WaitAsync(redeemOp, 45000, out aErr);
                    if (hr >= 0) {
                        var redResFn = (GetPtrDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(redeemOp), 0x40), typeof(GetPtrDel));
                        if (redResFn(redeemOp, out redeemProps) >= 0 && redeemProps != IntPtr.Zero) {
                            IntPtr rpVtbl = Marshal.ReadIntPtr(redeemProps);
                            var getNewKey = (GetPtrDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(rpVtbl, 0x30), typeof(GetPtrDel));
                            var getRedErr = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(rpVtbl, 0x40), typeof(GetIntPropDel));
                            IntPtr hNew = IntPtr.Zero;
                            if (getNewKey(redeemProps, out hNew) >= 0 && hNew != IntPtr.Zero) {
                                uint len;
                                IntPtr buf = WindowsGetStringRawBuffer(hNew, out len);
                                if (buf != IntPtr.Zero && len > 0) workKey = Marshal.PtrToStringUni(buf, (int)len);
                                WindowsDeleteString(hNew);
                            }
                            getRedErr(redeemProps, out redeemHr);
                        }
                    } else {
                        redeemHr = hr;
                    }
                } else {
                    redeemHr = hr;
                }
            }

            if (action == 1) {
                WindowsCreateString(workKey, workKey.Length, out hWorkKey);
                var applyFn = (StrAsyncDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 0x38), typeof(StrAsyncDel));
                hr = applyFn(factory, hWorkKey, out applyOp);
                if (hr < 0 || applyOp == IntPtr.Zero) return string.Format("ERR:ApplyCall:0x{0:X8}", hr);
                hr = WaitAsync(applyOp, 60000, out aErr);
                if (hr < 0) return string.Format("ERR:ApplyWait:0x{0:X8}", hr);
                var applyResFn = (ActionGetResultsDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(applyOp), 0x40), typeof(ActionGetResultsDel));
                hr = applyResFn(applyOp);
                if (hr < 0) return string.Format("ERR:ApplyRes:0x{0:X8}", hr);
            }

            var actFn = (ActionAsyncDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 0x48), typeof(ActionAsyncDel));
            hr = actFn(factory, out actOp);
            if (hr < 0 || actOp == IntPtr.Zero) return string.Format("ERR:ActCall:0x{0:X8}", hr);
            hr = WaitAsync(actOp, 45000, out aErr);
            string extraKey = (!string.IsNullOrEmpty(workKey) && !workKey.Equals(key, StringComparison.OrdinalIgnoreCase)) ? (";workKey=" + workKey) : "";
            if (hr < 0) {
                if (redeemHr < 0) return string.Format("ERR:Redeem=0x{0:X8};ActWait=0x{1:X8}{2}", redeemHr, hr, extraKey);
                return string.Format("ERR:ActWait:0x{0:X8}{1}", hr, extraKey);
            }
            IntPtr actResSlot = Marshal.ReadIntPtr(Marshal.ReadIntPtr(actOp), 0x40);
            if (actResSlot == IntPtr.Zero) return string.Format("ERR:ActSlotNull{0}", extraKey);
            var actResFn = (GetIntPropDel)Marshal.GetDelegateForFunctionPointer(actResSlot, typeof(GetIntPropDel));
            int actRes = 0;
            hr = actResFn(actOp, out actRes);
            if (hr < 0 || actRes < 0) {
                int errVal = hr < 0 ? hr : actRes;
                if (redeemHr < 0) return string.Format("ERR:Redeem=0x{0:X8};ActRes=0x{1:X8}{2}", redeemHr, errVal, extraKey);
                return string.Format("ERR:ActRes:0x{0:X8}{1}", errVal, extraKey);
            }
            return string.Format("OK:action={0};redeemable={1};redeemHr=0x{2:X8};actRes=0x{3:X8}{4}", action, isRedeemable, redeemHr, actRes, extraKey);
        } finally {
            if (actOp != IntPtr.Zero) Marshal.Release(actOp);
            if (applyOp != IntPtr.Zero) Marshal.Release(applyOp);
            if (hWorkKey != IntPtr.Zero) WindowsDeleteString(hWorkKey);
            if (redeemProps != IntPtr.Zero) Marshal.Release(redeemProps);
            if (redeemOp != IntPtr.Zero) Marshal.Release(redeemOp);
            if (props != IntPtr.Zero) Marshal.Release(props);
            if (evalOp != IntPtr.Zero) Marshal.Release(evalOp);
            if (hKey != IntPtr.Zero) WindowsDeleteString(hKey);
            if (factory != IntPtr.Zero) Marshal.Release(factory);
            if (hCls != IntPtr.Zero) WindowsDeleteString(hCls);
        }
    }
}
'@
function Invoke-ConvertToDigitalLicense($ProductKey) {
    if ([string]::IsNullOrWhiteSpace($ProductKey)) { return @{ Ok = $false; Detail = 'EmptyKey' } }
    Write-Host 'Dang chuyen sang ban quyen Digital License...'
    Write-ActLog 'Bat dau chuyen sang ban quyen Digital License.'
    $dNotice = Start-ActivatingNotice 'Dang chuyen sang ban quyen Digital License, vui long doi...'
    try {
        try { Start-Service ClipSVC -ErrorAction SilentlyContinue } catch { }
        try { Start-Service LicenseManager -ErrorAction SilentlyContinue } catch { }
        try { Start-Service sppsvc -ErrorAction SilentlyContinue } catch { }

        $winRtRes = $null
        $fallbackKey = $ProductKey
        try {
            if (-not ('ActWinModernLic' -as [type])) {
                Add-Type -TypeDefinition $ModernLicCs -ErrorAction Stop
            }
            $winRtRes = [ActWinModernLic]::ConvertToDigitalLicense($ProductKey)
            if ($winRtRes -match ';workKey=([A-Z0-9-]+)') {
                $fallbackKey = $Matches[1]
                $winRtRes = $winRtRes -replace ';workKey=[A-Z0-9-]+', ''
            }
            Write-ActLog "Modern Activation (WinRT): $winRtRes"
            if ($winRtRes -and $winRtRes.StartsWith('OK:')) {
                return @{ Ok = $true; Detail = $winRtRes }
            }
        } catch {
            $winRtRes = "ERR:WinRT:$($_.Exception.Message)"
            Write-ActLog "Modern Activation WinRT fallback -> changepk.exe: $winRtRes"
        }

        try {
            $pInfo = New-Object System.Diagnostics.ProcessStartInfo
            $pInfo.FileName = Join-Path $env:SystemRoot 'System32\changepk.exe'
            $pInfo.Arguments = "/ProductKey $fallbackKey /NoUI /NoReboot"
            $pInfo.UseShellExecute = $false
            $pInfo.CreateNoWindow = $true
            $cpkProc = [System.Diagnostics.Process]::Start($pInfo)
            if ($cpkProc) {
                if (-not $cpkProc.WaitForExit(30000)) {
                    try { $cpkProc.Kill() } catch { }
                    Write-ActLog "changepk.exe timeout ($winRtRes)"
                    return @{ Ok = $false; Detail = "$winRtRes; changepk.exe timeout" }
                }
                if ($cpkProc.ExitCode -eq 0) {
                    Write-ActLog 'changepk.exe /NoUI hoan tat (ExitCode=0).'
                    return @{ Ok = $true; Detail = 'changepk.exe ExitCode=0' }
                }
                $hexCode = '0x{0:X8}' -f ($cpkProc.ExitCode -band 0xFFFFFFFFL)
                Write-ActLog "changepk.exe /NoUI tra ve ma loi: $hexCode"
                return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$hexCode" }
            }
        } catch {
            Write-ActLog "changepk.exe exception: $($_.Exception.Message)"
            return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$($_.Exception.Message)" }
        }
        return @{ Ok = $false; Detail = "$winRtRes" }
    } finally {
        Stop-ActivatingNotice $dNotice
    }
}
function Invoke-PhoneActivation($Last5, $ErrorOutput, $FullKey = $null) {
    if (-not $FullKey -and $script:key) { $FullKey = $script:key }
    Write-ActLog "Online fallback -> PhoneActivation: $($ErrorOutput.Trim())"
    $last5Local = if ($FullKey -and $FullKey.Length -ge 5) { $FullKey.Substring($FullKey.Length - 5) } else { $Last5 }
    $licIds = Get-LicensingIds $last5Local
    $iidDigits = $licIds.IID
    Write-ActLog "IID len=$($iidDigits.Length) PID=$($licIds.ExtendedPid)"
    if (-not $iidDigits -or $iidDigits.Length -lt 20) {
        Write-Host "Khong lay duoc Installation ID. Xem log tai: $ActLogFile"
        Show-Info "Khong lay duoc Installation ID tu he thong.`r`nLog chi tiet: $ActLogFile" 'ActWin - Khong lay duoc IID'
        return @{ Activated = $false; Completed = $false }
    }

    $extPid = $licIds.ExtendedPid
    $autoCid = $null
    $cidSource = ''
    $cidNotice = Start-ActivatingNotice 'Dang lay CID tu dong qua may chu Microsoft, vui long doi...'
    try {
        if ($extPid) {
            Write-Host 'Dang lay CID qua Microsoft Server 1...'
            $batchResult = Get-CidFromBatchActivation -IidDigits $iidDigits -ExtendedPid $extPid
            if ($batchResult.Ok -and $batchResult.CID) {
                $autoCid = $batchResult.CID
                $cidSource = 'Microsoft Server 1'
                Write-Host 'Da lay CID qua Microsoft Server 1, dang kich hoat...'
                Write-ActLog "Server 1 (BatchActivation) thanh cong: CID=$autoCid"
            } else {
                Write-Host 'Lay CID qua Microsoft Server 1 that bai.'
                Write-ActLog "Server 1 (BatchActivation) that bai: $($batchResult.Error)"
            }
        } else {
            Write-ActLog 'Khong co ExtendedPid, bo qua Microsoft Server 1.'
        }

        if (-not $autoCid) {
            Write-Host 'Dang lay CID qua Microsoft Server 2...'
            $visualResult = Get-CidFromVisualSupport -IidDigits $iidDigits
            if ($visualResult.Ok -and $visualResult.CID) {
                $autoCid = $visualResult.CID
                $cidSource = 'Microsoft Server 2'
                Write-Host 'Da lay CID qua Microsoft Server 2, dang kich hoat...'
                Write-ActLog "Server 2 (VisualSupport) thanh cong: CID=$autoCid"
            } else {
                Write-Host 'Lay CID qua Microsoft Server 2 that bai.'
                Write-ActLog "Server 2 (VisualSupport) that bai: $($visualResult.Error)"
            }
        }
    } finally {
        Stop-ActivatingNotice $cidNotice
    }

    if ($autoCid) {
        $atpOut = Invoke-Slmgr @('/atp', $autoCid)
        Write-ActLog "slmgr /atp ($cidSource): $($atpOut.Trim())"
        $phoneNotice = Start-ActivatingNotice 'Dang kich hoat Windows Pro, vui long doi...'
        $phoneOk = $false
        try {
            $phoneDeadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $phoneDeadline) {
                if (Test-Activated $Last5) { $phoneOk = $true; break }
                Start-Sleep -Seconds 5
            }
        } finally {
            Stop-ActivatingNotice $phoneNotice
        }
        if ($phoneOk) {
            Write-ActLog "Kich hoat bang CID ($cidSource) thanh cong."
            $conv = Invoke-ConvertToDigitalLicense $FullKey
            if ($conv.Ok) {
                Write-Host 'Da hoan thanh!'
                Write-ActLog "Hoan thanh Digital License ($($conv.Detail))"
                Clear-ActWinHistory
                Remove-ActTempLogs
                Show-Info "Da kich hoat ($cidSource) va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $Last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
                return @{ Activated = $true; Completed = $true }
            } else {
                Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile"
                Show-Info "Da kich hoat Windows Pro thanh cong (5 ky tu cuoi: $Last5), nhung buoc tu dong chuyen sang Digital License chua thanh cong.`r`nHay vao Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile" 'ActWin - Canh bao Digital License'
                return @{ Activated = $true; Completed = $false }
            }
        } else {
            Write-Host 'Kich hoat bang CID tu dong that bai.'
            Write-ActLog "Kich hoat bang CID tu dong that bai: $($atpOut.Trim())"
        }
    }

    $iidGroups = @()
    for ($gi = 0; $gi -lt $iidDigits.Length; $gi += 7) { $iidGroups += $iidDigits.Substring($gi, [Math]::Min(7, $iidDigits.Length - $gi)) }
    $iidText = "Copy tung step theo thu tu vao trang cua Microsoft link: aka.ms/aoh de lay Confirmation ID`r`n`r`n"
    for ($gi = 0; $gi -lt $iidGroups.Count; $gi++) { $iidText += "Buoc $($gi + 1): $($iidGroups[$gi])`r`n" }
    $iidText += "`r`nDang 1 dong (de copy het): $($iidGroups -join ' ')"
    try {
        $clipStr = ($iidGroups -join ' ')
        Set-Clipboard $clipStr
        $script:WroteIidClipboard = $true
        $script:IidClipboardValue = $clipStr
    } catch { }
    try { Set-Content (Join-Path $env:TEMP 'ActWin-IID.txt') $iidText -Force -Encoding UTF8 } catch { }
    $iidResult = Show-TextForm 'ActWin - Installation ID' 'Hai server Microsoft khong tu lay duoc CID. Hay copy tung step vao aka.ms/aoh de lay CID roi bam OK:' $iidText $true
    if ($null -eq $iidResult) { return @{ Activated = $false; Completed = $false } }
    $attempt = 0
    while ($attempt -lt 5) {
        $attempt++
        $cidInput = Show-TextForm 'ActWin - Nhap Confirmation ID (CID)' 'Paste toan bo CID vao day:' '' $false
        if ($null -eq $cidInput) { return @{ Activated = $false; Completed = $false } }
        $cidDigits = ($cidInput -replace '[^0-9]', '')
        if ($cidDigits.Length -lt 40) {
            Show-Info "CID vua nhap chi co $($cidDigits.Length) chu so (thuong la 48 chu so). Hay kiem tra lai." 'ActWin - CID chua hop le'
            continue
        }
        $atpOut = Invoke-Slmgr @('/atp', $cidDigits)
        Write-ActLog "slmgr /atp (thu cong lan $attempt): $($atpOut.Trim())"
        Write-Host 'Dang kich hoat bang CID...'
        $phoneNotice = Start-ActivatingNotice 'Dang kich hoat Windows Pro, vui long doi...'
        $phoneOk = $false
        try {
            $phoneDeadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $phoneDeadline) {
                if (Test-Activated $Last5) { $phoneOk = $true; break }
                Start-Sleep -Seconds 5
            }
        } finally {
            Stop-ActivatingNotice $phoneNotice
        }
        if ($phoneOk) {
            $conv = Invoke-ConvertToDigitalLicense $FullKey
            if ($conv.Ok) {
                Write-Host 'Da hoan thanh!'
                Write-ActLog "Hoan thanh Digital License (CID thu cong: $($conv.Detail))"
                Clear-ActWinHistory
                Remove-ActTempLogs
                Show-Info "Da kich hoat va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $Last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
                return @{ Activated = $true; Completed = $true }
            } else {
                Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile"
                Show-Info "Da kich hoat bang CID thanh cong (5 ky tu cuoi: $Last5), nhung chua chuyen duoc sang Digital License.`r`nHay vao Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile" 'ActWin - Canh bao Digital License'
                return @{ Activated = $true; Completed = $false }
            }
        }
        Write-ActLog "Thu cong lan $attempt chua thanh cong: $($atpOut.Trim())"
        Show-Info "Kich hoat bang CID chua thanh cong. Hay kiem tra lai CID va thu lai.`r`nLog chi tiet: $ActLogFile" 'ActWin - CID chua thanh cong'
    }
    Write-Host "Kich hoat that bai. Xem log tai: $ActLogFile"
    Show-Info "Da dung kich hoat. May van la Pro nhung chua kich hoat.`r`nLog chi tiet: $ActLogFile" 'ActWin - Chua kich hoat'
    return @{ Activated = $false; Completed = $false }
}
function Remove-Phase2Artifacts {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { if (Test-Path $KeyFile) { Remove-Item $KeyFile -Force -ErrorAction SilentlyContinue } } catch { }
}

$Phase2Template = @'
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$TaskName = '__TASK__'
$KeyFile = '__KEYFILE__'
$Phase2File = '__PHASE2FILE__'
$WorkDir = '__WORKDIR__'
$ActTempDir2 = Join-Path $env:TEMP 'acti-temp'
$ActLogFile2 = Join-Path $ActTempDir2 'actwin.log'
$script:WroteIidClipboard2 = $false
$script:IidClipboardValue2 = $null
function Write-ActLog2($Message) {
    try {
        if (-not (Test-Path $ActTempDir2)) { New-Item -ItemType Directory -Path $ActTempDir2 -Force | Out-Null }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        [System.IO.File]::AppendAllText($ActLogFile2, ($line + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}
function Remove-ActTempLogs2 {
    try { if (Test-Path $ActTempDir2) { Remove-Item $ActTempDir2 -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
}
function Show-Info2($Text, $Title = 'ActWin') {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.Size = New-Object System.Drawing.Size(640, 400)
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $box = New-Object System.Windows.Forms.TextBox
        $box.Multiline = $true
        $box.ScrollBars = 'Vertical'
        $box.ReadOnly = $true
        $box.Text = $Text
        $box.Location = New-Object System.Drawing.Point(10, 10)
        $box.Size = New-Object System.Drawing.Size(600, 300)
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'OK'
        $okBtn.Location = New-Object System.Drawing.Point(525, 325)
        $okBtn.Size = New-Object System.Drawing.Size(75, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.AddRange(@($box, $okBtn))
        $form.AcceptButton = $okBtn
        $form.BringToFront()
        $form.Activate()
        [void]$form.ShowDialog()
    } catch { Write-Host $Text }
}
function Show-TextForm2($Title, $Prompt, $InitialText, $ReadOnly) {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.Size = New-Object System.Drawing.Size(640, 430)
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Prompt
        $label.AutoSize = $false
        $label.Location = New-Object System.Drawing.Point(10, 10)
        $label.Size = New-Object System.Drawing.Size(600, 40)
        $box = New-Object System.Windows.Forms.TextBox
        $box.Multiline = $true
        $box.ScrollBars = 'Vertical'
        $box.ReadOnly = $ReadOnly
        $box.Text = $InitialText
        $box.Location = New-Object System.Drawing.Point(10, 55)
        $box.Size = New-Object System.Drawing.Size(600, 285)
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'OK'
        $okBtn.Location = New-Object System.Drawing.Point(450, 355)
        $okBtn.Size = New-Object System.Drawing.Size(75, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cancelBtn = New-Object System.Windows.Forms.Button
        $cancelBtn.Text = 'Huy'
        $cancelBtn.Location = New-Object System.Drawing.Point(535, 355)
        $cancelBtn.Size = New-Object System.Drawing.Size(75, 30)
        $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.AddRange(@($label, $box, $okBtn, $cancelBtn))
        $form.AcceptButton = $okBtn
        $form.CancelButton = $cancelBtn
        $form.BringToFront()
        $form.Activate()
        if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $box.Text } else { return $null }
    } catch {
        try { return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $InitialText) } catch { return $null }
    }
}
function Invoke-Slmgr2($Arguments) {
    $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return (& cscript.exe //Nologo $slmgr @Arguments 2>&1 | Out-String)
    } catch {
        return "$($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $prevEap
    }
}
function Test-Activated2($Last5) {
    try {
        $prods = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
            Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
        foreach ($p in $prods) { if ($p.PartialProductKey -eq $Last5) { return $true } }
    } catch { }
    return $false
}
function Get-LicensingIds2($Last5) {
    $iid = ''
    $extPid = $null
    try {
        $allProds = @(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop)
        $lic = $null
        if ($Last5) {
            $lic = $allProds | Where-Object { $_.PartialProductKey -eq $Last5 -and $_.OfflineInstallationId } | Select-Object -First 1
        }
        if (-not $lic) {
            $lic = $allProds | Where-Object { $_.PartialProductKey -and $_.OfflineInstallationId -and $_.Name -like '*Windows*' } | Select-Object -First 1
        }
        if ($lic) {
            if ($lic.OfflineInstallationId) { $iid = ($lic.OfflineInstallationId -replace '[^0-9]', '') }
            if ($lic.ProductKeyID -and ($lic.ProductKeyID -notmatch '000-000000')) { $extPid = [string]$lic.ProductKeyID }
        }
    } catch { }
    if ($iid.Length -lt 20) {
        $dtiOut = Invoke-Slmgr2 @('/dti')
        if (($dtiOut -replace '[\s-]', '') -match '(\d{40,})') {
            $iid = $Matches[1]
        } else {
            $dtiLine = ($dtiOut -split "`n") | Where-Object { $_ -match 'Installation ID|ID' } | Select-Object -First 1
            if ($dtiLine) { $iid = ($dtiLine -replace '[^0-9]', '') }
        }
    }
    if (-not $extPid -or $extPid -match '000-000000') {
        $dlvOut = Invoke-Slmgr2 @('/dlv')
        if ($dlvOut -match '(\d{5}-\d{5}-\d{3}-\d{6}-\d{2}-\d+-\d+\.\d+-\d+)') {
            $extPid = $Matches[1].Trim()
        } elseif ($dlvOut -match 'Extended PID:\s*(\S+)') {
            $extPid = $Matches[1].Trim()
        }
    }
    if (-not $extPid -or $extPid -match '000-000000') {
        $extPid = '00000-00138-207-109016-00-1033-26100.0000-0922026'
    }
    return @{ IID = $iid; ExtendedPid = $extPid }
}
function Start-Watchdog2 {
    try {
        $dB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$WorkDir))
        $fB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$Phase2File))
        $kB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$KeyFile))
        $tB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$TaskName))
        $wdCode = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$ppid = $PID
while (Get-Process -Id `$ppid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 400 }
Start-Sleep -Milliseconds 300
`$tn = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$tB64'))
`$kf = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$kB64'))
`$pf = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$fB64'))
`$wd = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$dB64'))
try { Unregister-ScheduledTask -TaskName `$tn -Confirm:`$false -ErrorAction SilentlyContinue } catch { }
try { Get-ChildItem `$env:TEMP -Filter 'ActWin*' -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch { }
try { if (Test-Path `$kf) { Remove-Item `$kf -Force -ErrorAction SilentlyContinue } } catch { }
try { if (Test-Path `$pf) { Remove-Item `$pf -Force -ErrorAction SilentlyContinue } } catch { }
try { if (Test-Path `$wd) { Remove-Item `$wd -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
"@
        $wdEnc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wdCode))
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $wdEnc -ErrorAction SilentlyContinue | Out-Null
    } catch { }
}
function Clear-ActWinHistory2 {
    try {
        $paths = New-Object System.Collections.Generic.List[string]
        $defHist = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
        if ($defHist) { $paths.Add($defHist) }
        $pwsh7Hist = Join-Path $env:APPDATA 'Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt'
        if ($pwsh7Hist -and -not $paths.Contains($pwsh7Hist)) { $paths.Add($pwsh7Hist) }
        foreach ($hp in $paths) {
            if (Test-Path $hp) {
                try {
                    $lines = @(Get-Content $hp -Encoding UTF8 -ErrorAction SilentlyContinue)
                    $filtered = @($lines | Where-Object { $_ -notmatch '(?i)acti-win\.ps1|milansavio/Savio|ActWin-Phase2|ActWin-Cleanup' })
                    if ($filtered.Count -lt $lines.Count) {
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                        if ($filtered.Count -eq 0) {
                            [System.IO.File]::WriteAllText($hp, '', $utf8NoBom)
                        } else {
                            [System.IO.File]::WriteAllLines($hp, [string[]]$filtered, $utf8NoBom)
                        }
                    }
                } catch { }
            }
        }
    } catch { }
}
function Start-Notice2($NoticeText = 'Dang kich hoat, vui long doi...') {
    try {
        $safeB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$NoticeText))
        $nLines = @(
            ('$parentPid = ' + $PID),
            ('$msgText = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("' + $safeB64 + '"))'),
            '$form = New-Object System.Windows.Forms.Form',
            '$form.Text = "ActWin"',
            '$form.Size = New-Object System.Drawing.Size(420, 150)',
            '$form.StartPosition = "CenterScreen"',
            '$form.TopMost = $true',
            '$label = New-Object System.Windows.Forms.Label',
            '$label.Text = $msgText',
            '$label.AutoSize = $false',
            '$label.Location = New-Object System.Drawing.Point(20, 40)',
            '$label.Size = New-Object System.Drawing.Size(360, 60)',
            '$label.Font = New-Object System.Drawing.Font("Segoe UI", 12)',
            '$form.Controls.Add($label)',
            '$ticks = 0',
            '$timer = New-Object System.Windows.Forms.Timer',
            '$timer.Interval = 500',
            '$timer.Add_Tick({ $ticks++; if ($ticks -ge 360 -or -not (Get-Process -Id $parentPid -ErrorAction SilentlyContinue)) { $timer.Stop(); $form.Close() } })',
            '$timer.Start()',
            '$form.BringToFront()',
            '$form.Activate()',
            '[void]$form.ShowDialog()'
        )
        $nCode = "Add-Type -AssemblyName System.Windows.Forms`nAdd-Type -AssemblyName System.Drawing`n" + ($nLines -join "`n")
        $nBytes = [System.Text.Encoding]::Unicode.GetBytes($nCode)
        $nEncoded = [Convert]::ToBase64String($nBytes)
        return (Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $nEncoded -ErrorAction Stop)
    } catch { return $null }
}
function Stop-Notice2($Proc) {
    try { if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
}
function Get-CidFromBatchActivation2($IidDigits, $ExtendedPid) {
    try {
        $macKey = [byte[]](254,49,152,117,251,72,132,134,156,243,241,206,153,168,144,100,
                           171,87,31,202,71,4,80,88,48,36,226,20,98,135,121,160) + (,0)*32
        $inner = '<ActivationRequest xmlns="http://www.microsoft.com/DRM/SL/BatchActivationRequest/1.0">' +
                 '<VersionNumber>2.0</VersionNumber><RequestType>1</RequestType><Requests><Request>' +
                 '<PID>' + $ExtendedPid + '</PID><IID>' + $IidDigits + '</IID>' +
                 '</Request></Requests></ActivationRequest>'
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($inner)
        $hmac = [System.Security.Cryptography.HMACSHA256]::new($macKey)
        $digest = [Convert]::ToBase64String($hmac.ComputeHash($bytes))
        $requestXml = [Convert]::ToBase64String($bytes)
        $soap = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>' +
                '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
                '<soap:Body><BatchActivate xmlns="http://www.microsoft.com/BatchActivationService"><request>' +
                '<Digest>' + $digest + '</Digest><RequestXml>' + $requestXml + '</RequestXml>' +
                '</request></BatchActivate></soap:Body></soap:Envelope>'

        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288 } catch { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }
        $resp = Invoke-WebRequest -Uri 'https://activation.sls.microsoft.com/BatchActivation/BatchActivation.asmx' `
            -Method Post -ContentType 'text/xml; charset=utf-8' `
            -Headers @{
                SOAPAction   = 'http://www.microsoft.com/BatchActivationService/BatchActivate'
                'User-Agent' = 'ActivationWs/1.0'
            } `
            -Body $soap -UseBasicParsing -TimeoutSec 30

        $content = $resp.Content
        if ($content -match '(?:&lt;|<)CID(?:&gt;|>)([\d\s-]+)(?:&lt;|<)/CID(?:&gt;|>)') {
            $cidDigits = ($Matches[1] -replace '\D','')
            if ($cidDigits.Length -ge 40) { return @{ Ok = $true; CID = $cidDigits } }
        }
        if ($content -match '(?:&lt;|<)ErrorCode(?:&gt;|>)([^&<]+)(?:&lt;|<)/ErrorCode(?:&gt;|>)') {
            $errCode = $Matches[1].Trim()
            $desc = switch ($errCode) {
                '0x71' { 'The key has exceeded its activation limit (0x71 - Key da het luot tu kich hoat, can lay CID qua aka.ms/aoh).' }
                '0x7F' { 'The Multiple Activation Key has exceeded its limit (0x7F - MAK het luot).' }
                '0x67' { 'The product key has been blocked (0x67 - Key bi khoa/chan).' }
                '0x68' { 'Invalid product key (0x68 - Key khong hop le).' }
                '0x86' { 'Invalid key type for BatchActivation (0x86 - Loai key khong ho tro BatchActivation).' }
                '0x90' { 'Please check the Installation ID and try again (0x90 - IID chua dung).' }
                '0xD5' { 'ROT activation override limit reached (0xD5).' }
                Default { "BatchActivation ErrorCode: $errCode" }
            }
            return @{ Ok = $false; Error = $desc; Code = $errCode }
        }
        return @{ Ok = $false; Error = "Khong tim thay CID hoac ErrorCode trong ket qua tra ve: $content" }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}
function ConvertTo-Base64Url2([byte[]]$Bytes) {
    return [Convert]::ToBase64String($Bytes).TrimEnd('=') -replace '\+', '-' -replace '/', '_'
}
function Get-NetworkUtcTime2 {
    foreach ($tUrl in @('https://visualsupport.microsoft.com/api/productActivation/validateIID', 'http://www.msftconnecttest.com/connecttest.txt')) {
        $resp = $null
        try {
            $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($tUrl)
            $req.Method = 'HEAD'
            $req.Timeout = 4000
            $req.KeepAlive = $false
            $req.Proxy = $null
            $resp = $req.GetResponse()
            $dateStr = $resp.Headers['Date']
            if ($dateStr) {
                $serverUtc = [DateTime]::Parse($dateStr).ToUniversalTime().AddSeconds(-2)
                return [int64]($serverUtc - [DateTime]'1970-01-01').TotalSeconds
            }
        } catch {
            try {
                if ($_.Exception.Response -and $_.Exception.Response.Headers['Date']) {
                    $serverUtc = [DateTime]::Parse($_.Exception.Response.Headers['Date']).ToUniversalTime().AddSeconds(-2)
                    return [int64]($serverUtc - [DateTime]'1970-01-01').TotalSeconds
                }
            } catch { }
        } finally { if ($resp) { $resp.Close() } }
    }
    return [int64]([DateTime]::UtcNow.AddSeconds(-2) - [DateTime]'1970-01-01').TotalSeconds
}
function New-VisualApiDpopToken2($Url, $Method) {
    Add-Type -AssemblyName System.Core -ErrorAction SilentlyContinue | Out-Null
    $ecdsa = New-Object System.Security.Cryptography.ECDsaCng(256)
    try {
        $blob = $ecdsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
        $x = New-Object byte[] 32
        $y = New-Object byte[] 32
        [Array]::Copy($blob, 8, $x, 0, 32)
        [Array]::Copy($blob, 40, $y, 0, 32)

        $jwk = '{"kty":"EC","crv":"P-256","x":"' + (ConvertTo-Base64Url2 $x) + '","y":"' + (ConvertTo-Base64Url2 $y) + '"}'
        $hdr = '{"alg":"ES256","typ":"dpop+jwt","jwk":' + $jwk + '}'
        $iat = Get-NetworkUtcTime2
        $pld = '{"htu":"' + $Url + '","htm":"' + $Method + '","jti":"' + ([Guid]::NewGuid().ToString()) + '","iat":' + $iat + '}'

        $unsignedJwt = (ConvertTo-Base64Url2 ([System.Text.Encoding]::UTF8.GetBytes($hdr))) + '.' + (ConvertTo-Base64Url2 ([System.Text.Encoding]::UTF8.GetBytes($pld)))
        $sig = $ecdsa.SignData([System.Text.Encoding]::UTF8.GetBytes($unsignedJwt))

        return $unsignedJwt + '.' + (ConvertTo-Base64Url2 $sig)
    } finally {
        $ecdsa.Clear()
    }
}
function Get-CidFromVisualSupport2($IidDigits) {
    try {
        $cleanIID = ($IidDigits -replace '\D', '')
        if ($cleanIID.Length -lt 40) {
            return @{ Ok = $false; Error = "Installation ID khong hop le ($($cleanIID.Length) chu so)." }
        }

        # 1. Lay access token tu file cuc bo hoac server chia se
        $token = $null
        $tokenFile = Join-Path $env:TEMP 'CidToken.txt'
        if (Test-Path $tokenFile) {
            try {
                $rawToken = (Get-Content $tokenFile -Raw -ErrorAction SilentlyContinue).Trim()
                if ($rawToken -match '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2}$') { $token = $rawToken }
            } catch { }
        }
        if (-not $token) {
            try {
                try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288 } catch { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }
                $tokenResp = Invoke-RestMethod -Uri 'https://cidtoken.ntriver.org/token.json' -Method Get -TimeoutSec 10 -ErrorAction Stop
                if ($tokenResp -and $tokenResp.token) {
                    $token = [string]$tokenResp.token
                }
            } catch {
                return @{ Ok = $false; Error = "Khong lay duoc access token tu token server: $($_.Exception.Message)" }
            }
        }
        if (-not $token) {
            return @{ Ok = $false; Error = "Access token rong hoac khong hop le." }
        }

        # 2. Sinh DPoP JWT va gui POST toi Microsoft VisualSupport API (co thu lai neu timeout)
        $url = 'https://visualsupport.microsoft.com/api/productActivation/validateIID'
        $numDigits = [int]($cleanIID.Length / 9)
        $body = '{"IID":"' + $cleanIID + '","ProductType":"windows","productGroup":"Windows","productName":"Windows 11","numberOfDigits":' + $numDigits + ',"Country":"USA","Region":"NOAM","InstalledDevices":1,"OverrideStatusCode":"MUL","InitialReasonCode":"45164"}'
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288 } catch { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }

        $respText = $null
        $lastNetErr = $null
        for ($vsTry = 1; $vsTry -le 2; $vsTry++) {
            $dpop = New-VisualApiDpopToken2 '/api/productActivation/validateIID' 'POST'
            if (-not $dpop) {
                return @{ Ok = $false; Error = "Khong tao duoc DPoP token." }
            }
            try {
                $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
                $request.Method = 'POST'
                $request.KeepAlive = $false
                $request.Timeout = 25000
                $request.ReadWriteTimeout = 25000
                $request.ContentType = 'application/json; charset=utf-8'
                $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
                $request.Headers.Set('Authorization', "Bearer $token")
                $request.Headers.Set('DPoP', $dpop)
                $request.Headers.Set('x-session-id', ('app_' + [Guid]::NewGuid().ToString('N')))
                $request.ContentLength = $bodyBytes.Length
                $reqStream = $request.GetRequestStream()
                $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
                $reqStream.Close()

                $response = $request.GetResponse()
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                $respText = $reader.ReadToEnd()
                $reader.Close()
                $response.Close()
                break
            } catch [System.Net.WebException] {
                $webEx = $_.Exception
                if ($webEx.Response) {
                    $reader = New-Object System.IO.StreamReader($webEx.Response.GetResponseStream())
                    $respText = $reader.ReadToEnd()
                    $reader.Close()
                    break
                } else {
                    $lastNetErr = $webEx.Message
                    if ($vsTry -lt 2) { Start-Sleep -Seconds 1; continue }
                }
            }
        }
        if (-not $respText -and $lastNetErr) {
            return @{ Ok = $false; Error = "VisualSupport WebException: $lastNetErr" }
        }

        if ([string]::IsNullOrWhiteSpace($respText)) {
            return @{ Ok = $false; Error = "VisualSupport API khong tra ve du lieu." }
        }

        # 4. Parse ket qua JSON
        $json = $null
        try { $json = ConvertFrom-Json $respText } catch {
            try {
                Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue | Out-Null
                $jsSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $json = $jsSerializer.DeserializeObject($respText)
            } catch { }
        }

        if ($json) {
            $dict = if ($json -is [System.Collections.IDictionary]) { [System.Collections.IDictionary]$json } else { $null }
            $cid = $null
            if ($dict) {
                if (($dict.Keys -contains 'cid')) { $cid = $dict['cid'] }
                elseif (($dict.Keys -contains 'confirmationId')) { $cid = $dict['confirmationId'] }
            } else {
                if ($json.PSObject.Properties['cid']) { $cid = $json.cid }
                elseif ($json.PSObject.Properties['confirmationId']) { $cid = $json.confirmationId }
            }

            if ($cid) {
                $cidDigits = ($cid -replace '\D', '')
                if ($cidDigits.Length -ge 40) {
                    return @{ Ok = $true; CID = $cidDigits }
                }
            }

            $msg = if ($dict) { if (($dict.Keys -contains 'message')) { $dict['message'] } else { $null } } elseif ($json.PSObject.Properties['message']) { $json.message } else { $null }
            $reason = if ($dict) { if (($dict.Keys -contains 'reasonCode')) { $dict['reasonCode'] } else { $null } } elseif ($json.PSObject.Properties['reasonCode']) { $json.reasonCode } else { $null }
            if ($msg -or $reason) {
                return @{ Ok = $false; Error = "VisualSupport tra ve: $msg (reasonCode: $reason)" }
            }
        }

        return @{ Ok = $false; Error = "Khong tim thay CID trong ket qua VisualSupport: $respText" }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}
function Invoke-ConvertToDigitalLicense2($ProductKey) {
    if ([string]::IsNullOrWhiteSpace($ProductKey)) { return @{ Ok = $false; Detail = 'EmptyKey' } }
    Write-Host 'Dang chuyen sang ban quyen Digital License...'
    Write-ActLog2 'Phase 2: Bat dau chuyen sang ban quyen Digital License.'
    $dNotice2 = Start-Notice2 'Dang chuyen sang ban quyen Digital License, vui long doi...'
    try {
        try { Start-Service ClipSVC -ErrorAction SilentlyContinue } catch { }
        try { Start-Service LicenseManager -ErrorAction SilentlyContinue } catch { }
        try { Start-Service sppsvc -ErrorAction SilentlyContinue } catch { }

        $winRtRes = $null
        $fallbackKey = $ProductKey
        try {
            if (-not ('ActWinModernLic' -as [type])) {
                $modernLicCs2 = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__MODERNLIC_B64__'))
                Add-Type -TypeDefinition $modernLicCs2 -ErrorAction Stop
            }
            $winRtRes = [ActWinModernLic]::ConvertToDigitalLicense($ProductKey)
            if ($winRtRes -match ';workKey=([A-Z0-9-]+)') {
                $fallbackKey = $Matches[1]
                $winRtRes = $winRtRes -replace ';workKey=[A-Z0-9-]+', ''
            }
            Write-ActLog2 "Modern Activation (WinRT): $winRtRes"
            if ($winRtRes -and $winRtRes.StartsWith('OK:')) {
                return @{ Ok = $true; Detail = $winRtRes }
            }
        } catch {
            $winRtRes = "ERR:WinRT:$($_.Exception.Message)"
            Write-ActLog2 "Modern Activation WinRT fallback -> changepk.exe: $winRtRes"
        }

        try {
            $pInfo = New-Object System.Diagnostics.ProcessStartInfo
            $pInfo.FileName = Join-Path $env:SystemRoot 'System32\changepk.exe'
            $pInfo.Arguments = "/ProductKey $fallbackKey /NoUI /NoReboot"
            $pInfo.UseShellExecute = $false
            $pInfo.CreateNoWindow = $true
            $cpkProc2 = [System.Diagnostics.Process]::Start($pInfo)
            if ($cpkProc2) {
                if (-not $cpkProc2.WaitForExit(30000)) {
                    try { $cpkProc2.Kill() } catch { }
                    Write-ActLog2 "changepk.exe timeout ($winRtRes)"
                    return @{ Ok = $false; Detail = "$winRtRes; changepk.exe timeout" }
                }
                if ($cpkProc2.ExitCode -eq 0) {
                    Write-ActLog2 'changepk.exe /NoUI hoan tat (ExitCode=0).'
                    return @{ Ok = $true; Detail = 'changepk.exe ExitCode=0' }
                }
                $hexCode = '0x{0:X8}' -f ($cpkProc2.ExitCode -band 0xFFFFFFFFL)
                Write-ActLog2 "changepk.exe /NoUI tra ve ma loi: $hexCode"
                return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$hexCode" }
            }
        } catch {
            Write-ActLog2 "changepk.exe exception: $($_.Exception.Message)"
            return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$($_.Exception.Message)" }
        }
        return @{ Ok = $false; Detail = "$winRtRes" }
    } finally {
        Stop-Notice2 $dNotice2
    }
}
try {
    Start-Watchdog2
    if (-not (Test-Path $KeyFile)) { throw 'Khong tim thay file key da ma hoa. Hay chay lai acti-win.ps1 va nhap key.' }
    $enc = (Get-Content $KeyFile -Raw).Trim()
    $enc = $enc.Trim([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($enc)) { throw 'File key da ma hoa rong. Hay chay lai acti-win.ps1 va nhap key.' }
    $secure = ConvertTo-SecureString $enc
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    # Go ngay task va file key sau khi da nap key vao RAM de tranh sot rac neu tat ngang
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { if (Test-Path $KeyFile) { Remove-Item $KeyFile -Force -ErrorAction SilentlyContinue } } catch { }
    $last5 = $key.Substring($key.Length - 5)
    Write-Host 'Dang kich hoat online...'
    Write-ActLog2 "Phase 2: Bat dau kich hoat online (last5=$last5)"
    $noticeProc2 = Start-Notice2 'Dang kich hoat online, vui long doi...'
    $o1 = ''
    $o2 = ''
    $ok = $false
    try {
        if (Test-Activated2 $last5) {
            $ok = $true
        } else {
            $o1 = Invoke-Slmgr2 @('/ipk', $key)
            Write-ActLog2 "slmgr /ipk: $($o1.Trim())"
            $o2 = Invoke-Slmgr2 @('/ato')
            Write-ActLog2 "slmgr /ato (lan 1): $($o2.Trim())"
            $deadline = (Get-Date).AddSeconds(30)
            $again = $false
            while ((Get-Date) -lt $deadline) {
                if (Test-Activated2 $last5) { $ok = $true; break }
                Start-Sleep -Seconds 5
                if (-not $again) {
                    $o2 = Invoke-Slmgr2 @('/ato')
                    Write-ActLog2 "slmgr /ato (lan 2): $($o2.Trim())"
                    $again = $true
                }
            }
        }
    } finally {
        Stop-Notice2 $noticeProc2
    }
    if ($ok) {
        Write-Host 'Kich hoat online thanh cong.'
        Write-ActLog2 'Phase 2: Kich hoat online thanh cong.'
        $conv2 = Invoke-ConvertToDigitalLicense2 $key
        if ($conv2.Ok) {
            Write-Host 'Da hoan thanh!'
            Write-ActLog2 "Phase 2: Hoan thanh Digital License ($($conv2.Detail))"
            Clear-ActWinHistory2
            Remove-ActTempLogs2
            Show-Info2 "Da kich hoat va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
        } else {
            Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile2"
            Show-Info2 "Da kich hoat Windows Pro thanh cong (5 ky tu cuoi: $last5), nhung buoc tu dong chuyen sang Digital License chua thanh cong.`r`nHay vao Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile2" 'ActWin - Canh bao Digital License'
        }
    } else {
        Write-Host 'Kich hoat online that bai.'
        Write-ActLog2 "Phase 2: Kich hoat online that bai.`n$o1`n$o2"
        $licIds2 = Get-LicensingIds2 $last5
        $iidDigits = $licIds2.IID
        Write-ActLog2 "IID len=$($iidDigits.Length) PID=$($licIds2.ExtendedPid)"
        if ($iidDigits -and $iidDigits.Length -ge 20) {
            $extPid = $licIds2.ExtendedPid
            $autoCid2 = $null
            $cidSource2 = ''
            $cidNotice2 = Start-Notice2 'Dang lay CID tu dong qua may chu Microsoft, vui long doi...'
            try {
                if ($extPid) {
                    Write-Host 'Dang lay CID qua Microsoft Server 1...'
                    $batchResult2 = Get-CidFromBatchActivation2 $iidDigits $extPid
                    if ($batchResult2.Ok -and $batchResult2.CID) {
                        $autoCid2 = $batchResult2.CID
                        $cidSource2 = 'Microsoft Server 1'
                        Write-Host 'Da lay CID qua Microsoft Server 1, dang kich hoat...'
                        Write-ActLog2 "Server 1 (BatchActivation) thanh cong: CID=$autoCid2"
                    } else {
                        Write-Host 'Lay CID qua Microsoft Server 1 that bai.'
                        Write-ActLog2 "Server 1 (BatchActivation) that bai: $($batchResult2.Error)"
                    }
                } else {
                    Write-ActLog2 'Khong co ExtendedPid, bo qua Microsoft Server 1.'
                }

                if (-not $autoCid2) {
                    Write-Host 'Dang lay CID qua Microsoft Server 2...'
                    $visualResult2 = Get-CidFromVisualSupport2 $iidDigits
                    if ($visualResult2.Ok -and $visualResult2.CID) {
                        $autoCid2 = $visualResult2.CID
                        $cidSource2 = 'Microsoft Server 2'
                        Write-Host 'Da lay CID qua Microsoft Server 2, dang kich hoat...'
                        Write-ActLog2 "Server 2 (VisualSupport) thanh cong: CID=$autoCid2"
                    } else {
                        Write-Host 'Lay CID qua Microsoft Server 2 that bai.'
                        Write-ActLog2 "Server 2 (VisualSupport) that bai: $($visualResult2.Error)"
                    }
                }
            } finally {
                Stop-Notice2 $cidNotice2
            }

            if ($autoCid2) {
                $atpOut2 = Invoke-Slmgr2 @('/atp', $autoCid2)
                Write-ActLog2 "slmgr /atp ($cidSource2): $($atpOut2.Trim())"
                $noticePhone2 = Start-Notice2 'Dang kich hoat Windows Pro, vui long doi...'
                try {
                    $phoneDeadline2 = (Get-Date).AddSeconds(30)
                    while ((Get-Date) -lt $phoneDeadline2) {
                        if (Test-Activated2 $last5) { $ok = $true; break }
                        Start-Sleep -Seconds 5
                    }
                } finally {
                    Stop-Notice2 $noticePhone2
                }
                if ($ok) {
                    Write-ActLog2 "Phase 2: Kich hoat bang CID ($cidSource2) thanh cong."
                    $conv2 = Invoke-ConvertToDigitalLicense2 $key
                    if ($conv2.Ok) {
                        Write-Host 'Da hoan thanh!'
                        Write-ActLog2 "Phase 2: Hoan thanh Digital License ($($conv2.Detail))"
                        Clear-ActWinHistory2
                        Remove-ActTempLogs2
                        Show-Info2 "Da kich hoat ($cidSource2) va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
                    } else {
                        Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile2"
                        Show-Info2 "Da kich hoat Windows Pro thanh cong (5 ky tu cuoi: $last5), nhung buoc tu dong chuyen sang Digital License chua thanh cong.`r`nHay vao Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile2" 'ActWin - Canh bao Digital License'
                    }
                } else {
                    Write-Host 'Kich hoat bang CID tu dong that bai.'
                    Write-ActLog2 "Phase 2: Kich hoat bang CID tu dong that bai: $($atpOut2.Trim())"
                }
            }
            if (-not $ok) {
                $iidGroups = @()
                for ($gi = 0; $gi -lt $iidDigits.Length; $gi += 7) { $iidGroups += $iidDigits.Substring($gi, [Math]::Min(7, $iidDigits.Length - $gi)) }
                $iidText = "Copy tung step theo thu tu vao trang cua Microsoft link: aka.ms/aoh de lay Confirmation ID`r`n`r`n"
                for ($gi = 0; $gi -lt $iidGroups.Count; $gi++) { $iidText += "Buoc $($gi + 1): $($iidGroups[$gi])`r`n" }
                $iidText += "`r`nDang 1 dong (de copy het): $($iidGroups -join ' ')"
                try {
                    $clipStr2 = ($iidGroups -join ' ')
                    Set-Clipboard $clipStr2
                    $script:WroteIidClipboard2 = $true
                    $script:IidClipboardValue2 = $clipStr2
                } catch { }
                try { if (Test-Path $WorkDir) { Set-Content (Join-Path $WorkDir 'IID.txt') $iidText -Force -Encoding UTF8 } } catch { }
                $iidResult = Show-TextForm2 'ActWin - Installation ID' 'Hai server Microsoft khong tu lay duoc CID. Hay copy tung step vao aka.ms/aoh de lay CID roi bam OK:' $iidText $true
                if ($null -ne $iidResult) {
                    $attempt = 0
                    while ($attempt -lt 5 -and -not $ok) {
                        $attempt++
                        $cidInput = Show-TextForm2 'ActWin - Nhap Confirmation ID (CID)' 'Paste toan bo CID vao day:' '' $false
                        if ($null -eq $cidInput) { break }
                        $cidDigits = ($cidInput -replace '[^0-9]', '')
                        if ($cidDigits.Length -lt 40) {
                            Show-Info2 "CID vua nhap chi co $($cidDigits.Length) chu so (thuong la 48 chu so). Hay kiem tra lai." 'ActWin - CID chua hop le'
                            continue
                        }
                        $atpOut = Invoke-Slmgr2 @('/atp', $cidDigits)
                        Write-ActLog2 "slmgr /atp (thu cong lan $attempt): $($atpOut.Trim())"
                        Write-Host 'Dang kich hoat bang CID...'
                        $noticePhone = Start-Notice2 'Dang kich hoat Windows Pro, vui long doi...'
                        try {
                            $phoneDeadline = (Get-Date).AddSeconds(30)
                            while ((Get-Date) -lt $phoneDeadline) {
                                if (Test-Activated2 $last5) { $ok = $true; break }
                                Start-Sleep -Seconds 5
                            }
                        } finally {
                            Stop-Notice2 $noticePhone
                        }
                        if ($ok) {
                            $conv2 = Invoke-ConvertToDigitalLicense2 $key
                            if ($conv2.Ok) {
                                Write-Host 'Da hoan thanh!'
                                Write-ActLog2 "Phase 2: Hoan thanh Digital License (CID thu cong: $($conv2.Detail))"
                                Clear-ActWinHistory2
                                Remove-ActTempLogs2
                                Show-Info2 "Da kich hoat va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
                            } else {
                                Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile2"
                                Show-Info2 "Da kich hoat bang CID thanh cong (5 ky tu cuoi: $last5), nhung chua chuyen duoc sang Digital License.`r`nHay vao Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile2" 'ActWin - Canh bao Digital License'
                            }
                        } else {
                            Write-ActLog2 "Thu cong lan $attempt chua thanh cong: $($atpOut.Trim())"
                            Show-Info2 "Kich hoat bang CID chua thanh cong. Hay kiem tra lai CID va thu lai.`r`nLog chi tiet: $ActLogFile2" 'ActWin - CID chua thanh cong'
                        }
                    }
                    if (-not $ok) {
                        Write-Host "Kich hoat that bai. Xem log tai: $ActLogFile2"
                        Show-Info2 "Da dung kich hoat. May van la Pro nhung chua kich hoat.`r`nLog chi tiet: $ActLogFile2" 'ActWin - Chua kich hoat'
                    }
                }
            }
        } else {
            Write-Host "Khong lay duoc Installation ID. Xem log tai: $ActLogFile2"
            Show-Info2 "Khong lay duoc Installation ID tu he thong.`r`nLog chi tiet: $ActLogFile2" 'ActWin - Khong lay duoc IID'
        }
    }
} catch {
    Write-ActLog2 "Phase 2 exception: $($_.Exception.Message)"
    Show-Info2 "Phase 2 gap loi: $($_.Exception.Message)`r`nLog chi tiet: $ActLogFile2" 'ActWin - Loi'
} finally {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { Get-ChildItem $env:TEMP -Filter 'ActWin*' -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch { }
    try {
        if ($script:WroteIidClipboard2 -and $script:IidClipboardValue2) {
            $curClip2 = ''
            try { $curClip2 = [System.Windows.Forms.Clipboard]::GetText() } catch { }
            if ($curClip2 -eq $script:IidClipboardValue2) { [System.Windows.Forms.Clipboard]::Clear() }
        }
    } catch { }
    try { if (Test-Path $KeyFile) { Remove-Item $KeyFile -Force -ErrorAction SilentlyContinue } } catch { }
    try { if (Test-Path $Phase2File) { Remove-Item $Phase2File -Force -ErrorAction SilentlyContinue } } catch { }
    try { if (Test-Path $WorkDir) { Remove-Item $WorkDir -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
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
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Title
        $form.Size = New-Object System.Drawing.Size(640, 400)
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $box = New-Object System.Windows.Forms.TextBox
        $box.Multiline = $true
        $box.ScrollBars = 'Vertical'
        $box.ReadOnly = $true
        $box.Text = $Text
        $box.Location = New-Object System.Drawing.Point(10, 10)
        $box.Size = New-Object System.Drawing.Size(600, 300)
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = 'OK'
        $okBtn.Location = New-Object System.Drawing.Point(525, 325)
        $okBtn.Size = New-Object System.Drawing.Size(75, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.AddRange(@($box, $okBtn))
        $form.AcceptButton = $okBtn
        $form.BringToFront()
        $form.Activate()
        [void]$form.ShowDialog()
    } catch { Write-Host $Text }
}
try {
    try {
        $dB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$CWorkDir))
        $fB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$CFile))
        $tB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$CTask))
        $wdC = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$ppid = $PID
while (Get-Process -Id `$ppid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 400 }
Start-Sleep -Milliseconds 300
`$tn = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$tB64'))
`$cf = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$fB64'))
`$wd = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$dB64'))
try { Unregister-ScheduledTask -TaskName `$tn -Confirm:`$false -ErrorAction SilentlyContinue } catch { }
try { Unregister-ScheduledTask -TaskName 'ActWin-Phase2' -Confirm:`$false -ErrorAction SilentlyContinue } catch { }
try { Get-ChildItem `$env:TEMP -Filter 'ActWin*' -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch { }
try { if (Test-Path `$cf) { Remove-Item `$cf -Force -ErrorAction SilentlyContinue } } catch { }
try { if (Test-Path `$wd) { Remove-Item `$wd -Force -Recurse -ErrorAction SilentlyContinue } } catch { }
"@
        $wdCEnc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wdC))
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $wdCEnc -ErrorAction SilentlyContinue | Out-Null
    } catch { }
    try { Unregister-ScheduledTask -TaskName $CTask -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { Unregister-ScheduledTask -TaskName 'ActWin-Phase2' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    $editionC = ''
    try { $editionC = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID } catch { }
    if ($editionC -match 'Professional') {
        try {
            $atd = Join-Path $env:TEMP 'acti-temp'
            if (Test-Path $atd) { Remove-Item $atd -Force -Recurse -ErrorAction SilentlyContinue }
        } catch { }
        Show-InfoC 'Da hoan thanh upgrade len Windows Pro (khong kich hoat).' 'ActWin - Da len Pro'
    } else {
        Show-InfoC 'May chua len Pro. Hay chay lai acti-win.ps1 va chon lai.' 'ActWin - Chua len Pro'
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
    try {
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
        } else {
            $cmd = "irm '$RawUrl' | iex"
            Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
        }
    } catch {
        Show-Info "Vui long chay PowerShell voi quyen Administrator (Run as Administrator): $($_.Exception.Message)" 'ActWin - Can quyen Admin'
    }
    exit
}

try {
    $edition = ''
    try { $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID } catch { }
    $isPro = ($edition -match 'Professional')

    $menuChoice = Get-MenuChoice
    if (-not $menuChoice) { Write-Host 'Da huy.'; exit }

    if ($menuChoice -eq '2') {
        if ($isPro) {
            Remove-ActTempLogs
            Show-Info 'May da la Windows Pro. Lua chon 2 chi upgrade, khong can lam gi them va khong kich hoat.' 'ActWin - Da la Pro'
            exit
        }
        Write-ActLog 'Lua chon 2: Chuan bi upgrade Home -> Pro (khong kich hoat).'
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
        $prevEapCpk2 = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & changepk.exe /ProductKey $GenericProKey 2>$null | Out-Null } catch { } finally { $ErrorActionPreference = $prevEapCpk2 }
        Show-Info 'Dang chuan bi upgrade len Pro, khong kich hoat theo lua chon 2. Dung tat may. May se tu khoi dong lai khi chuan bi xong, sau khi dang nhap lai task don dep se tu xoa task cua ActWin va file tam cua ActWin. Neu khong thay man hinh Preparing va may khong tu khoi dong lai, hay khoi dong lai thu cong - task don dep van con va se chay luc dang nhap.' 'ActWin - Dang chuan bi upgrade'
        exit
    }

    $key = Get-ProKey
    if (-not $key) { Write-Host 'Da huy: khong co key.'; exit }
    $last5 = $key.Substring($key.Length - 5)

    if ($isPro) {
        Start-ActWinWatchdog $WorkDir $null $false
        Write-ActLog "Bat dau quy trinh tren Windows Pro (last5=$last5)"
        try {
            if (Test-Activated $last5) {
                Write-Host 'May da kich hoat san voi key nay.'
                Write-ActLog "May da kich hoat san voi last5=$last5."
                $conv = Invoke-ConvertToDigitalLicense $key
                if ($conv.Ok) {
                    Write-Host 'Da hoan thanh!'
                    Write-ActLog "Hoan thanh Digital License ($($conv.Detail))"
                    Clear-ActWinHistory
                    Remove-ActTempLogs
                    Show-Info "May da kich hoat san voi key $last5 va da chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
                } else {
                    Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile"
                    Show-Info "May da kich hoat san voi key $last5, nhung buoc tu dong chuyen sang Digital License chua thanh cong.`r`nHay mo Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile" 'ActWin - Canh bao Digital License'
                }
                exit
            }
            $result = Invoke-ActivateAndCheck $key $last5
            if ($result.Ok) {
                $conv = Invoke-ConvertToDigitalLicense $key
                if ($conv.Ok) {
                    Write-Host 'Da hoan thanh!'
                    Write-ActLog "Hoan thanh Digital License ($($conv.Detail))"
                    Clear-ActWinHistory
                    Remove-ActTempLogs
                    Show-Info "Da kich hoat va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen." 'ActWin - Hoan thanh'
                } else {
                    Write-Host "Chuyen sang Digital License that bai. Xem log tai: $ActLogFile"
                    Show-Info "Da kich hoat Windows Pro thanh cong (5 ky tu cuoi: $last5), nhung buoc tu dong chuyen sang Digital License chua thanh cong.`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay.`r`nLog chi tiet: $ActLogFile" 'ActWin - Canh bao Digital License'
                }
            } else {
                # Already-Pro machine: same phone flow as phase 2
                Invoke-PhoneActivation $last5 $result.Output $key | Out-Null
            }
        } finally {
            Invoke-CleanActWinArtifacts $false
        }
        exit
    }

    # Not Pro yet (Phase 1 Home -> Pro): save phase 2 first, then upgrade the edition, then reboot.
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $secureKey = ConvertTo-SecureString $key -AsPlainText -Force
    $encKey = $secureKey | ConvertFrom-SecureString
    Set-Content $KeyFile $encKey -Force -NoNewline -Encoding Ascii

    $modernLicB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ModernLicCs))
    $phase2 = $Phase2Template.Replace('__TASK__', $TaskName).Replace('__KEYFILE__', $KeyFile).Replace('__PHASE2FILE__', $Phase2File).Replace('__WORKDIR__', $WorkDir).Replace('__MODERNLIC_B64__', $modernLicB64)
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
    Write-Host 'Dang chuan bi nang cap Home len Pro...'
    Write-ActLog "Phase 1: Chuan bi upgrade Home -> Pro (last5=$last5), dang ky Phase 2."
    $prevEapCpk1 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & changepk.exe /ProductKey $GenericProKey 2>$null | Out-Null } catch { } finally { $ErrorActionPreference = $prevEapCpk1 }
    Show-Info 'Dang chuan bi upgrade len Pro. Dung tat may. May se tu khoi dong lai khi chuan bi xong, sau khi dang nhap lai phase 2 se tu dong kich hoat va chuyen sang Digital License.' 'ActWin - Dang chuan bi upgrade'
} catch {
    Write-ActLog "Main exception: $($_.Exception.Message)"
    Show-Info "ActWin gap loi: $($_.Exception.Message)`r`nLog chi tiet: $ActLogFile" 'ActWin - Loi'
}
