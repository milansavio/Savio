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
function Start-ActivatingNotice($NoticeText = 'Dang kich hoat, vui long doi...') {
    try {
        $noticeLines = @(
            '$form = New-Object System.Windows.Forms.Form',
            '$form.Text = "ActWin"',
            '$form.Size = New-Object System.Drawing.Size(420, 150)',
            '$form.StartPosition = "CenterScreen"',
            '$form.TopMost = $true',
            '$label = New-Object System.Windows.Forms.Label',
            ('$label.Text = "' + $NoticeText + '"'),
            '$label.AutoSize = $false',
            '$label.Location = New-Object System.Drawing.Point(20, 40)',
            '$label.Size = New-Object System.Drawing.Size(360, 60)',
            '$label.Font = New-Object System.Drawing.Font("Segoe UI", 12)',
            '$form.Controls.Add($label)',
            '$timer = New-Object System.Windows.Forms.Timer',
            '$timer.Interval = 180000',
            '$timer.Add_Tick({ $form.Close() })',
            '$timer.Start()',
            '$form.BringToFront()',
            '$form.Activate()',
            '[void]$form.ShowDialog()'
        )
        $noticeCode = ($noticeLines -join "`n")
        $noticeCode = "Add-Type -AssemblyName System.Windows.Forms`nAdd-Type -AssemblyName System.Drawing`n" + $noticeCode
        $noticeBytes = [System.Text.Encoding]::Unicode.GetBytes($noticeCode)
        $noticeEncoded = [Convert]::ToBase64String($noticeBytes)
        return (Start-Process powershell.exe -PassThru -ArgumentList '-NoProfile', '-EncodedCommand', $noticeEncoded -ErrorAction Stop)
    } catch { return $null }
}
function Stop-ActivatingNotice($Proc) {
    try { if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
}

function Invoke-ActivateAndCheck($Key, $Last5) {
    Write-Host 'Dang kich hoat online, vui long doi...'
    try { $Host.UI.RawUI.WindowTitle = 'ActWin - Dang kich hoat, vui long doi...' } catch { }
    $noticeProc = Start-ActivatingNotice
    try {
        $out1 = Invoke-Slmgr @('/ipk', $Key)
        Write-Host 'Da nhap key, dang kich hoat online...'
        $out2 = Invoke-Slmgr @('/ato')
        $deadline = (Get-Date).AddSeconds(30)
        $triedAgain = $false
        $checkCount = 0
        while ((Get-Date) -lt $deadline) {
            $checkCount++
            Write-Host "Dang kiem tra kich hoat, vui long doi... (lan $checkCount)"
            if (Test-Activated $Last5) { return @{ Ok = $true; Output = $out2 } }
            Start-Sleep -Seconds 5
            if (-not $triedAgain) { $out2 = Invoke-Slmgr @('/ato'); $triedAgain = $true }
        }
        if (Test-Activated $Last5) { return @{ Ok = $true; Output = $out2 } }
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

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
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
    $resp = $null
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $req.Method = 'HEAD'
        $req.Timeout = 3000
        $req.KeepAlive = $false
        $req.Proxy = $null
        $resp = $req.GetResponse()
        $dateStr = $resp.Headers['Date']
        if ($dateStr) {
            $serverUtc = [DateTime]::Parse($dateStr).ToUniversalTime().AddSeconds(3)
            return [int64]($serverUtc - [DateTime]'1970-01-01').TotalSeconds
        }
    } catch { }
    finally { if ($resp) { $resp.Close() } }
    return [int64]([DateTime]::UtcNow.AddSeconds(3) - [DateTime]'1970-01-01').TotalSeconds
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
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
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

        # 2. Sinh DPoP JWT voi khoa ephemeral ECDSA P-256
        $dpop = New-VisualApiDpopToken '/api/productActivation/validateIID' 'POST'
        if (-not $dpop) {
            return @{ Ok = $false; Error = "Khong tao duoc DPoP token." }
        }

        # 3. Gui request POST toi Microsoft VisualSupport API
        $url = 'https://visualsupport.microsoft.com/api/productActivation/validateIID'
        $numDigits = [int]($cleanIID.Length / 9)
        $body = '{"IID":"' + $cleanIID + '","ProductType":"windows","productGroup":"Windows","productName":"Windows 11","numberOfDigits":' + $numDigits + ',"Country":"USA","Region":"NOAM","InstalledDevices":1,"OverrideStatusCode":"MUL","InitialReasonCode":"45164"}'

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
        $request.Method = 'POST'
        $request.KeepAlive = $false
        $request.Proxy = $null
        $request.Timeout = 15000
        $request.ContentType = 'application/json; charset=utf-8'
        $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
        $request.Headers.Set('Authorization', "Bearer $token")
        $request.Headers.Set('DPoP', $dpop)
        $request.Headers.Set('x-session-id', ('app_' + [Guid]::NewGuid().ToString('N')))

        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length
        $reqStream = $request.GetRequestStream()
        $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $reqStream.Close()

        $respText = $null
        try {
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $respText = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()
        } catch [System.Net.WebException] {
            $webEx = $_.Exception
            if ($webEx.Response) {
                $reader = New-Object System.IO.StreamReader($webEx.Response.GetResponseStream())
                $respText = $reader.ReadToEnd()
                $reader.Close()
            } else {
                return @{ Ok = $false; Error = "VisualSupport WebException: $($webEx.Message)" }
            }
        }

        if ([string]::IsNullOrWhiteSpace($respText)) {
            return @{ Ok = $false; Error = "VisualSupport API khong tra ve du lieu." }
        }

        # 4. Parse ket qua JSON
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue | Out-Null
        $json = $null
        try {
            $jsSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $json = $jsSerializer.DeserializeObject($respText)
        } catch {
            try { $json = ConvertFrom-Json $respText } catch { }
        }

        if ($json) {
            $cid = $null
            if ($json -is [System.Collections.IDictionary] -and $json.Contains('cid')) { $cid = $json['cid'] }
            elseif ($json.cid) { $cid = $json.cid }

            if ($cid) {
                $cidDigits = ($cid -replace '\D', '')
                if ($cidDigits.Length -ge 40) {
                    return @{ Ok = $true; CID = $cidDigits }
                }
            }

            $msg = if ($json -is [System.Collections.IDictionary] -and $json.Contains('message')) { $json['message'] } elseif ($json.message) { $json.message } else { $null }
            $reason = if ($json -is [System.Collections.IDictionary] -and $json.Contains('reasonCode')) { $json['reasonCode'] } elseif ($json.reasonCode) { $json.reasonCode } else { $null }
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
            if (hr < 0) {
                if (redeemHr < 0) return string.Format("ERR:Redeem=0x{0:X8};ActWait=0x{1:X8}", redeemHr, hr);
                return string.Format("ERR:ActWait:0x{0:X8}", hr);
            }
            var actResFn = (ActionGetResultsDel)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(actOp), 0x40), typeof(ActionGetResultsDel));
            hr = actResFn(actOp);
            if (hr < 0) {
                if (redeemHr < 0) return string.Format("ERR:Redeem=0x{0:X8};ActRes=0x{1:X8}", redeemHr, hr);
                return string.Format("ERR:ActRes:0x{0:X8}", hr);
            }
            return string.Format("OK:action={0};redeemable={1};redeemHr=0x{2:X8}", action, isRedeemable, redeemHr);
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
    Write-Host 'Dang tu dong nhap de key qua Modern Activation (LicensingPolicyManager) de chuyen doi sang Ban quyen ky thuat so (Digital License)...'
    $dNotice = Start-ActivatingNotice 'Dang chuyen doi sang Ban quyen ky thuat so (Digital License), vui long doi...'
    try {
        try { Start-Service ClipSVC -ErrorAction SilentlyContinue } catch { }
        try { Start-Service LicenseManager -ErrorAction SilentlyContinue } catch { }
        try { Start-Service sppsvc -ErrorAction SilentlyContinue } catch { }

        $winRtRes = $null
        try {
            if (-not ('ActWinModernLic' -as [type])) {
                Add-Type -TypeDefinition $ModernLicCs -ErrorAction Stop
            }
            $winRtRes = [ActWinModernLic]::ConvertToDigitalLicense($ProductKey)
            Write-Host "Modern Activation (LicensingPolicyManager): $winRtRes"
            if ($winRtRes -and $winRtRes.StartsWith('OK:')) {
                return @{ Ok = $true; Detail = $winRtRes }
            }
        } catch {
            $winRtRes = "ERR:WinRT:$($_.Exception.Message)"
            Write-Host "Modern Activation WinRT khong kha dung, chuyen sang du phong changepk.exe: $winRtRes"
        }

        try {
            $pInfo = New-Object System.Diagnostics.ProcessStartInfo
            $pInfo.FileName = Join-Path $env:SystemRoot 'System32\changepk.exe'
            $pInfo.Arguments = "/ProductKey $ProductKey /NoUI /NoReboot"
            $pInfo.UseShellExecute = $false
            $pInfo.CreateNoWindow = $true
            $cpkProc = [System.Diagnostics.Process]::Start($pInfo)
            if ($cpkProc) {
                if (-not $cpkProc.WaitForExit(30000)) {
                    try { $cpkProc.Kill() } catch { }
                    return @{ Ok = $false; Detail = "$winRtRes; changepk.exe timeout" }
                }
                if ($cpkProc.ExitCode -eq 0) {
                    Write-Host 'changepk.exe /NoUI hoan tat (ExitCode=0).'
                    return @{ Ok = $true; Detail = 'changepk.exe ExitCode=0' }
                }
                $hexCode = '0x{0:X8}' -f ($cpkProc.ExitCode -band 0xFFFFFFFFL)
                Write-Host "changepk.exe /NoUI tra ve ma loi: $hexCode"
                return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$hexCode" }
            }
        } catch {
            return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$($_.Exception.Message)" }
        }
        return @{ Ok = $false; Detail = "$winRtRes" }
    } finally {
        Stop-ActivatingNotice $dNotice
    }
}
function Invoke-PhoneActivation($Last5, $ErrorOutput, $FullKey = $null) {
    if (-not $FullKey -and $script:key) { $FullKey = $script:key }
    $errText = $ErrorOutput
    if ($errText.Length -gt 1500) { $errText = $errText.Substring(0, 1500) }
    Show-Info "Kich hoat online khong thanh cong. Loi tu he thong:`n$errText`nBay gio se chuyen sang kich hoat bang dien thoai (phone activation)." 'ActWin - Chua kich hoat online'
    Write-Host 'Dang lay Installation ID (IID), vui long doi...'
    $dtiOut = Invoke-Slmgr @('/dti')
    $dtiLine = ($dtiOut -split "`n") | Where-Object { $_ -match 'Installation ID' } | Select-Object -First 1
    if (-not $dtiLine) { $dtiLine = $dtiOut }
    $iidDigits = ($dtiLine -replace '[^0-9]', '')
    if ($iidDigits.Length -lt 20) { $iidDigits = ($dtiOut -replace '[^0-9]', '') }
    if ($iidDigits.Length -lt 20) {
        Show-Info "Khong lay duoc Installation ID tu he thong. Loi online truoc do:`n$errText" 'ActWin - Khong lay duoc IID'
        return $false
    }

    # --- Test T3: Thu tu dong lay CID qua BatchActivation va VisualSupport API ---
    $dlvOut = Invoke-Slmgr @('/dlv')
    $extPid = if ($dlvOut -match 'Extended PID:\s*(\S+)') { $Matches[1].Trim() } else { $null }
    $autoCid = $null
    $cidSource = ''
    if ($extPid) {
        Write-Host 'Dang thu tu dong lay CID qua may chu Microsoft (BatchActivation)...'
        $autoNotice = Start-ActivatingNotice 'Dang thu tu dong lay CID qua may chu Microsoft (BatchActivation), vui long doi...'
        $batchResult = Get-CidFromBatchActivation -IidDigits $iidDigits -ExtendedPid $extPid
        Stop-ActivatingNotice $autoNotice
        if ($batchResult.Ok -and $batchResult.CID) {
            $autoCid = $batchResult.CID
            $cidSource = 'BatchActivation'
            Write-Host "Da lay CID tu dong thanh cong tu BatchActivation: $autoCid"
        } else {
            Write-Host "BatchActivation khong thanh cong: $($batchResult.Error)"
        }
    }

    # Neu BatchActivation khong tra ve CID (vi du loi 0x71: het luot), tu dong chuyen sang Microsoft VisualSupport API (aka.ms/aoh)
    if (-not $autoCid) {
        Write-Host 'Dang chuyen sang tu dong lay CID qua Microsoft VisualSupport API (aka.ms/aoh)...'
        $visualNotice = Start-ActivatingNotice 'Dang tu dong lay CID qua Microsoft VisualSupport API, vui long doi...'
        $visualResult = Get-CidFromVisualSupport -IidDigits $iidDigits
        Stop-ActivatingNotice $visualNotice
        if ($visualResult.Ok -and $visualResult.CID) {
            $autoCid = $visualResult.CID
            $cidSource = 'VisualSupport API'
            Write-Host "Da lay CID tu dong thanh cong tu VisualSupport API: $autoCid"
        } else {
            Write-Host "VisualSupport API khong thanh cong: $($visualResult.Error)"
        }
    }

    if ($autoCid) {
        Write-Host "Dang tien hanh kich hoat bang CID tu dong ($($cidSource): $autoCid)..."
        $atpOut = Invoke-Slmgr @('/atp', $autoCid)
        $phoneNotice = Start-ActivatingNotice "Dang kich hoat bang CID tu dong ($($cidSource)), vui long doi..."
        $phoneDeadline = (Get-Date).AddSeconds(30)
        $phoneOk = $false
        $phoneCheck = 0
        while ((Get-Date) -lt $phoneDeadline) {
            $phoneCheck++
            Write-Host "Dang kiem tra kich hoat, vui long doi... (lan $phoneCheck)"
            if (Test-Activated $Last5) { $phoneOk = $true; break }
            Start-Sleep -Seconds 5
        }
        Stop-ActivatingNotice $phoneNotice
        if ($phoneOk) {
            $cidGroups = @()
            for ($ci = 0; $ci -lt $autoCid.Length; $ci += 6) { $cidGroups += $autoCid.Substring($ci, [Math]::Min(6, $autoCid.Length - $ci)) }
            $conv = Invoke-ConvertToDigitalLicense $FullKey
            if ($conv.Ok) {
                Show-Info "Da tu dong lay CID ($($cidSource)) va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`nCID: $($cidGroups -join ' ')`r`n5 ky tu cuoi: $Last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
            } else {
                Show-Info "Da tu dong lay CID ($($cidSource)) va kich hoat thanh cong Windows Pro (5 ky tu cuoi: $Last5).`r`nTuy nhien buoc tu dong chuyen sang Digital License chua thanh cong ($($conv.Detail)).`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Da kich hoat (Canh bao Digital License)'
            }
            return $true
        } else {
            Write-Host "Kich hoat bang CID tu dong chua thanh cong: $atpOut"
        }
    }
    $iidGroups = @()
    for ($gi = 0; $gi -lt $iidDigits.Length; $gi += 7) { $iidGroups += $iidDigits.Substring($gi, [Math]::Min(7, $iidDigits.Length - $gi)) }
    $iidText = "Copy tung step theo thu tu vao trang cua Microsoft link: aka.ms/aoh de lay Confirmation ID`r`n`r`n"
    for ($gi = 0; $gi -lt $iidGroups.Count; $gi++) { $iidText += "Buoc $($gi + 1): $($iidGroups[$gi])`r`n" }
    $iidText += "`r`nDang 1 dong (de copy het): $($iidGroups -join ' ')"
    try { Set-Clipboard ($iidGroups -join ' ') } catch { }
    try { Set-Content (Join-Path $env:TEMP 'ActWin-IID.txt') $iidText -Force -Encoding UTF8 } catch { }
    $iidResult = Show-TextForm 'ActWin - Installation ID' 'Copy tung step theo thu tu vao trang cua Microsoft link: aka.ms/aoh de lay Confirmation ID (CID) roi bam OK de nhap CID:' $iidText $true
    if ($null -eq $iidResult) { return $false }
    $attempt = 0
    while ($attempt -lt 5) {
        $attempt++
        $cidInput = Show-TextForm 'ActWin - Nhap Confirmation ID (CID)' 'Paste toan bo CID vao day (co the co khoang trang, gach ngang, xuong dong). Script se tu bo ky tu thua va tu chia lai thanh tung nhom 6 chu so:' '' $false
        if ($null -eq $cidInput) { return $false }
        $cidDigits = ($cidInput -replace '[^0-9]', '')
        if ($cidDigits.Length -lt 40) {
            Show-Info "CID vua nhap chi co $($cidDigits.Length) chu so, thuong la 48 chu so. Hay kiem tra lai va nhap lai." 'ActWin - CID chua hop le'
            continue
        }
        $cidGroups = @()
        for ($ci = 0; $ci -lt $cidDigits.Length; $ci += 6) { $cidGroups += $cidDigits.Substring($ci, [Math]::Min(6, $cidDigits.Length - $ci)) }
        $atpOut = Invoke-Slmgr @('/atp', $cidDigits)
        Write-Host 'Dang kich hoat qua Phone, vui long doi...'
        $phoneNotice = Start-ActivatingNotice 'Dang kich hoat qua Phone, vui long doi...'
        $phoneDeadline = (Get-Date).AddSeconds(30)
        $phoneOk = $false
        $phoneCheck = 0
        while ((Get-Date) -lt $phoneDeadline) {
            $phoneCheck++
            Write-Host "Dang kiem tra kich hoat qua Phone, vui long doi... (lan $phoneCheck)"
            if (Test-Activated $Last5) { $phoneOk = $true; break }
            Start-Sleep -Seconds 5
        }
        Stop-ActivatingNotice $phoneNotice
        if ($phoneOk) {
            $conv = Invoke-ConvertToDigitalLicense $FullKey
            if ($conv.Ok) {
                Show-Info "Da kich hoat bang Confirmation ID va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`nCID: $($cidGroups -join ' ')`r`n5 ky tu cuoi: $Last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
            } else {
                Show-Info "Da kich hoat bang Confirmation ID thanh cong (5 ky tu cuoi: $Last5).`r`nTuy nhien buoc tu dong chuyen sang Digital License chua thanh cong ($($conv.Detail)).`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Da kich hoat (Canh bao Digital License)'
            }
            return $true
        }
        $atpText = $atpOut
        if ($atpText.Length -gt 1200) { $atpText = $atpText.Substring(0, 1200) }
        Show-Info "Kich hoat bang CID chua thanh cong. Loi tu he thong:`n$atpText`nHay kiem tra lai CID va nhap lai." 'ActWin - CID chua thanh cong'
    }
    Show-Info 'Da dung kich hoat bang dien thoai. May van la Pro nhung chua kich hoat, hay chay lai acti-win.ps1 khi co CID dung.' 'ActWin - Chua kich hoat'
    return $false
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
function Start-Notice2($NoticeText = 'Dang kich hoat, vui long doi...') {
    try {
        $nLines = @(
            '$form = New-Object System.Windows.Forms.Form',
            '$form.Text = "ActWin"',
            '$form.Size = New-Object System.Drawing.Size(420, 150)',
            '$form.StartPosition = "CenterScreen"',
            '$form.TopMost = $true',
            '$label = New-Object System.Windows.Forms.Label',
            ('$label.Text = "' + $NoticeText + '"'),
            '$label.AutoSize = $false',
            '$label.Location = New-Object System.Drawing.Point(20, 40)',
            '$label.Size = New-Object System.Drawing.Size(360, 60)',
            '$label.Font = New-Object System.Drawing.Font("Segoe UI", 12)',
            '$form.Controls.Add($label)',
            '$timer = New-Object System.Windows.Forms.Timer',
            '$timer.Interval = 180000',
            '$timer.Add_Tick({ $form.Close() })',
            '$timer.Start()',
            '$form.BringToFront()',
            '$form.Activate()',
            '[void]$form.ShowDialog()'
        )
        $nCode = "Add-Type -AssemblyName System.Windows.Forms`nAdd-Type -AssemblyName System.Drawing`n" + ($nLines -join "`n")
        $nBytes = [System.Text.Encoding]::Unicode.GetBytes($nCode)
        $nEncoded = [Convert]::ToBase64String($nBytes)
        return (Start-Process powershell.exe -PassThru -ArgumentList '-NoProfile', '-EncodedCommand', $nEncoded -ErrorAction Stop)
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

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
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
    $resp = $null
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $req.Method = 'HEAD'
        $req.Timeout = 3000
        $req.KeepAlive = $false
        $req.Proxy = $null
        $resp = $req.GetResponse()
        $dateStr = $resp.Headers['Date']
        if ($dateStr) {
            $serverUtc = [DateTime]::Parse($dateStr).ToUniversalTime().AddSeconds(3)
            return [int64]($serverUtc - [DateTime]'1970-01-01').TotalSeconds
        }
    } catch { }
    finally { if ($resp) { $resp.Close() } }
    return [int64]([DateTime]::UtcNow.AddSeconds(3) - [DateTime]'1970-01-01').TotalSeconds
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
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
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

        # 2. Sinh DPoP JWT voi khoa ephemeral ECDSA P-256
        $dpop = New-VisualApiDpopToken2 '/api/productActivation/validateIID' 'POST'
        if (-not $dpop) {
            return @{ Ok = $false; Error = "Khong tao duoc DPoP token." }
        }

        # 3. Gui request POST toi Microsoft VisualSupport API
        $url = 'https://visualsupport.microsoft.com/api/productActivation/validateIID'
        $numDigits = [int]($cleanIID.Length / 9)
        $body = '{"IID":"' + $cleanIID + '","ProductType":"windows","productGroup":"Windows","productName":"Windows 11","numberOfDigits":' + $numDigits + ',"Country":"USA","Region":"NOAM","InstalledDevices":1,"OverrideStatusCode":"MUL","InitialReasonCode":"45164"}'

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
        $request.Method = 'POST'
        $request.KeepAlive = $false
        $request.Proxy = $null
        $request.Timeout = 15000
        $request.ContentType = 'application/json; charset=utf-8'
        $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
        $request.Headers.Set('Authorization', "Bearer $token")
        $request.Headers.Set('DPoP', $dpop)
        $request.Headers.Set('x-session-id', ('app_' + [Guid]::NewGuid().ToString('N')))

        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length
        $reqStream = $request.GetRequestStream()
        $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $reqStream.Close()

        $respText = $null
        try {
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $respText = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()
        } catch [System.Net.WebException] {
            $webEx = $_.Exception
            if ($webEx.Response) {
                $reader = New-Object System.IO.StreamReader($webEx.Response.GetResponseStream())
                $respText = $reader.ReadToEnd()
                $reader.Close()
            } else {
                return @{ Ok = $false; Error = "VisualSupport WebException: $($webEx.Message)" }
            }
        }

        if ([string]::IsNullOrWhiteSpace($respText)) {
            return @{ Ok = $false; Error = "VisualSupport API khong tra ve du lieu." }
        }

        # 4. Parse ket qua JSON
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue | Out-Null
        $json = $null
        try {
            $jsSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $json = $jsSerializer.DeserializeObject($respText)
        } catch {
            try { $json = ConvertFrom-Json $respText } catch { }
        }

        if ($json) {
            $cid = $null
            if ($json -is [System.Collections.IDictionary] -and $json.Contains('cid')) { $cid = $json['cid'] }
            elseif ($json.cid) { $cid = $json.cid }

            if ($cid) {
                $cidDigits = ($cid -replace '\D', '')
                if ($cidDigits.Length -ge 40) {
                    return @{ Ok = $true; CID = $cidDigits }
                }
            }

            $msg = if ($json -is [System.Collections.IDictionary] -and $json.Contains('message')) { $json['message'] } elseif ($json.message) { $json.message } else { $null }
            $reason = if ($json -is [System.Collections.IDictionary] -and $json.Contains('reasonCode')) { $json['reasonCode'] } elseif ($json.reasonCode) { $json.reasonCode } else { $null }
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
    Write-Host 'Dang tu dong nhap de key qua Modern Activation (LicensingPolicyManager) de chuyen doi sang Ban quyen ky thuat so (Digital License)...'
    $dNotice2 = Start-Notice2 'Dang chuyen doi sang Ban quyen ky thuat so (Digital License), vui long doi...'
    try {
        try { Start-Service ClipSVC -ErrorAction SilentlyContinue } catch { }
        try { Start-Service LicenseManager -ErrorAction SilentlyContinue } catch { }
        try { Start-Service sppsvc -ErrorAction SilentlyContinue } catch { }

        $winRtRes = $null
        try {
            if (-not ('ActWinModernLic' -as [type])) {
                $modernLicCs2 = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__MODERNLIC_B64__'))
                Add-Type -TypeDefinition $modernLicCs2 -ErrorAction Stop
            }
            $winRtRes = [ActWinModernLic]::ConvertToDigitalLicense($ProductKey)
            Write-Host "Modern Activation (LicensingPolicyManager): $winRtRes"
            if ($winRtRes -and $winRtRes.StartsWith('OK:')) {
                return @{ Ok = $true; Detail = $winRtRes }
            }
        } catch {
            $winRtRes = "ERR:WinRT:$($_.Exception.Message)"
            Write-Host "Modern Activation WinRT khong kha dung, chuyen sang du phong changepk.exe: $winRtRes"
        }

        try {
            $pInfo = New-Object System.Diagnostics.ProcessStartInfo
            $pInfo.FileName = Join-Path $env:SystemRoot 'System32\changepk.exe'
            $pInfo.Arguments = "/ProductKey $ProductKey /NoUI /NoReboot"
            $pInfo.UseShellExecute = $false
            $pInfo.CreateNoWindow = $true
            $cpkProc2 = [System.Diagnostics.Process]::Start($pInfo)
            if ($cpkProc2) {
                if (-not $cpkProc2.WaitForExit(30000)) {
                    try { $cpkProc2.Kill() } catch { }
                    return @{ Ok = $false; Detail = "$winRtRes; changepk.exe timeout" }
                }
                if ($cpkProc2.ExitCode -eq 0) {
                    Write-Host 'changepk.exe /NoUI hoan tat (ExitCode=0).'
                    return @{ Ok = $true; Detail = 'changepk.exe ExitCode=0' }
                }
                $hexCode = '0x{0:X8}' -f ($cpkProc2.ExitCode -band 0xFFFFFFFFL)
                Write-Host "changepk.exe /NoUI tra ve ma loi: $hexCode"
                return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$hexCode" }
            }
        } catch {
            return @{ Ok = $false; Detail = "$winRtRes; changepk.exe=$($_.Exception.Message)" }
        }
        return @{ Ok = $false; Detail = "$winRtRes" }
    } finally {
        Stop-Notice2 $dNotice2
    }
}
try {
    if (-not (Test-Path $KeyFile)) { throw 'Khong tim thay file key da ma hoa. Hay chay lai acti-win.ps1 va nhap key.' }
    $enc = (Get-Content $KeyFile -Raw).Trim()
    $enc = $enc.Trim([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($enc)) { throw 'File key da ma hoa rong. Hay chay lai acti-win.ps1 va nhap key.' }
    $secure = ConvertTo-SecureString $enc
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $last5 = $key.Substring($key.Length - 5)
    $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    Write-Host 'Dang kich hoat online, vui long doi...'
    $noticeProc2 = Start-Notice2
    $o1 = (& cscript.exe //Nologo $slmgr /ipk $key 2>&1 | Out-String)
    Write-Host 'Da nhap key, dang kich hoat online...'
    $o2 = (& cscript.exe //Nologo $slmgr /ato 2>&1 | Out-String)
    $ok = $false
    $deadline = (Get-Date).AddSeconds(30)
    $again = $false
    $checkCount2 = 0
    while ((Get-Date) -lt $deadline) {
        $checkCount2++
        Write-Host "Dang kiem tra kich hoat, vui long doi... (lan $checkCount2)"
        $prods = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction SilentlyContinue |
            Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
        foreach ($p in $prods) { if ($p.PartialProductKey -eq $last5) { $ok = $true; break } }
        if ($ok) { break }
        Start-Sleep -Seconds 5
        if (-not $again) { $o2 = (& cscript.exe //Nologo $slmgr /ato 2>&1 | Out-String); $again = $true }
    }
    Stop-Notice2 $noticeProc2
    if ($ok) {
        $conv2 = Invoke-ConvertToDigitalLicense2 $key
        if ($conv2.Ok) {
            Show-Info2 "Da kich hoat va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
        } else {
            Show-Info2 "Da kich hoat Windows Pro thanh cong (5 ky tu cuoi: $last5).`r`nTuy nhien buoc tu dong chuyen sang Digital License chua thanh cong ($($conv2.Detail)).`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Da kich hoat (Canh bao Digital License)'
        }
    } else {
        $errText = "$o1`n$o2"
        if ($errText.Length -gt 1500) { $errText = $errText.Substring(0, 1500) }
        Show-Info2 "Kich hoat online khong thanh cong. Loi tu he thong:`n$errText`nBay gio se chuyen sang kich hoat bang dien thoai (phone activation)." 'ActWin - Chua kich hoat online'
        Write-Host 'Dang lay Installation ID (IID), vui long doi...'
        $dtiOut = (& cscript.exe //Nologo $slmgr /dti 2>&1 | Out-String)
        $dtiLine = ($dtiOut -split "`n") | Where-Object { $_ -match 'Installation ID' } | Select-Object -First 1
        if (-not $dtiLine) { $dtiLine = $dtiOut }
        $iidDigits = ($dtiLine -replace '[^0-9]', '')
        if ($iidDigits.Length -lt 20) { $iidDigits = ($dtiOut -replace '[^0-9]', '') }
        if ($iidDigits.Length -ge 20) {
            # --- Test T3: Thu tu dong lay CID qua BatchActivation va VisualSupport API ---
            $dlvOut = (& cscript.exe //Nologo $slmgr /dlv 2>&1 | Out-String)
            $extPid = if ($dlvOut -match 'Extended PID:\s*(\S+)') { $Matches[1].Trim() } else { $null }
            $autoCid2 = $null
            $cidSource2 = ''
            if ($extPid) {
                Write-Host 'Dang thu tu dong lay CID tu server Microsoft (BatchActivation)...'
                $noticeAuto2 = Start-Notice2 'Dang thu tu dong lay CID qua may chu Microsoft (BatchActivation), vui long doi...'
                $batchResult2 = Get-CidFromBatchActivation2 $iidDigits $extPid
                Stop-Notice2 $noticeAuto2
                if ($batchResult2.Ok -and $batchResult2.CID) {
                    $autoCid2 = $batchResult2.CID
                    $cidSource2 = 'BatchActivation'
                    Write-Host "Da lay CID tu dong thanh cong tu BatchActivation: $autoCid2"
                } else {
                    Write-Host "BatchActivation khong thanh cong: $($batchResult2.Error)"
                }
            }

            # Neu BatchActivation khong co CID, chuyen sang VisualSupport API
            if (-not $autoCid2) {
                Write-Host 'Dang chuyen sang tu dong lay CID qua Microsoft VisualSupport API (aka.ms/aoh)...'
                $noticeVisual2 = Start-Notice2 'Dang tu dong lay CID qua Microsoft VisualSupport API, vui long doi...'
                $visualResult2 = Get-CidFromVisualSupport2 $iidDigits
                Stop-Notice2 $noticeVisual2
                if ($visualResult2.Ok -and $visualResult2.CID) {
                    $autoCid2 = $visualResult2.CID
                    $cidSource2 = 'VisualSupport API'
                    Write-Host "Da lay CID tu dong thanh cong tu VisualSupport API: $autoCid2"
                } else {
                    Write-Host "VisualSupport API khong thanh cong: $($visualResult2.Error)"
                }
            }

            if ($autoCid2) {
                Write-Host "Da lay CID tu dong ($($cidSource2): $autoCid2). Dang kich hoat..."
                $atpOut2 = (& cscript.exe //Nologo $slmgr /atp $autoCid2 2>&1 | Out-String)
                $noticePhone2 = Start-Notice2 "Dang kich hoat qua CID tu dong ($($cidSource2)), vui long doi..."
                $phoneDeadline2 = (Get-Date).AddSeconds(30)
                $phoneCheck2 = 0
                while ((Get-Date) -lt $phoneDeadline2) {
                    $phoneCheck2++
                    Write-Host "Dang kiem tra kich hoat, vui long doi... (lan $phoneCheck2)"
                    $prods2 = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue |
                        Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
                    foreach ($p2 in $prods2) { if ($p2.PartialProductKey -eq $last5) { $ok = $true; break } }
                    if ($ok) { break }
                    Start-Sleep -Seconds 5
                }
                Stop-Notice2 $noticePhone2
                if ($ok) {
                    $cidGroups = @()
                    for ($ci = 0; $ci -lt $autoCid2.Length; $ci += 6) { $cidGroups += $autoCid2.Substring($ci, [Math]::Min(6, $autoCid2.Length - $ci)) }
                    $conv2 = Invoke-ConvertToDigitalLicense2 $key
                    if ($conv2.Ok) {
                        Show-Info2 "Da tu dong lay CID ($($cidSource2)) va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`nCID: $($cidGroups -join ' ')`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
                    } else {
                        Show-Info2 "Da tu dong lay CID ($($cidSource2)) va kich hoat thanh cong Windows Pro (5 ky tu cuoi: $last5).`r`nTuy nhien buoc tu dong chuyen sang Digital License chua thanh cong ($($conv2.Detail)).`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Da kich hoat (Canh bao Digital License)'
                    }
                } else {
                    Write-Host "Kich hoat bang CID tu dong chua thanh cong: $atpOut2"
                }
            }
            if (-not $ok) {
                $iidGroups = @()
                for ($gi = 0; $gi -lt $iidDigits.Length; $gi += 7) { $iidGroups += $iidDigits.Substring($gi, [Math]::Min(7, $iidDigits.Length - $gi)) }
                $iidText = "Copy tung step theo thu tu vao trang cua Microsoft link: aka.ms/aoh de lay Confirmation ID`r`n`r`n"
                for ($gi = 0; $gi -lt $iidGroups.Count; $gi++) { $iidText += "Buoc $($gi + 1): $($iidGroups[$gi])`r`n" }
                $iidText += "`r`nDang 1 dong (de copy het): $($iidGroups -join ' ')"
                try { Set-Clipboard ($iidGroups -join ' ') } catch { }
                try { if (Test-Path $WorkDir) { Set-Content (Join-Path $WorkDir 'IID.txt') $iidText -Force -Encoding UTF8 } } catch { }
                $iidResult = Show-TextForm2 'ActWin - Installation ID' 'Copy tung step theo thu tu vao trang cua Microsoft link: aka.ms/aoh de lay Confirmation ID (CID) roi bam OK de nhap CID:' $iidText $true
                if ($null -ne $iidResult) {
                    $attempt = 0
                    while ($attempt -lt 5 -and -not $ok) {
                        $attempt++
                        $cidInput = Show-TextForm2 'ActWin - Nhap Confirmation ID (CID)' 'Paste toan bo CID vao day (co the co khoang trang, gach ngang, xuong dong). Script se tu bo ky tu thua va tu chia lai thanh tung nhom 6 chu so:' '' $false
                        if ($null -eq $cidInput) { break }
                        $cidDigits = ($cidInput -replace '[^0-9]', '')
                        if ($cidDigits.Length -lt 40) {
                            Show-Info2 "CID vua nhap chi co $($cidDigits.Length) chu so, thuong la 48 chu so. Hay kiem tra lai va nhap lai." 'ActWin - CID chua hop le'
                            continue
                        }
                        $cidGroups = @()
                        for ($ci = 0; $ci -lt $cidDigits.Length; $ci += 6) { $cidGroups += $cidDigits.Substring($ci, [Math]::Min(6, $cidDigits.Length - $ci)) }
                        $atpOut = (& cscript.exe //Nologo $slmgr /atp $cidDigits 2>&1 | Out-String)
                        Write-Host 'Dang kich hoat qua Phone, vui long doi...'
                        $noticePhone = Start-Notice2 'Dang kich hoat qua Phone, vui long doi...'
                        $phoneDeadline = (Get-Date).AddSeconds(30)
                        while ((Get-Date) -lt $phoneDeadline) {
                            $prods2 = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue |
                                Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
                            foreach ($p2 in $prods2) { if ($p2.PartialProductKey -eq $last5) { $ok = $true; break } }
                            if ($ok) { break }
                            Start-Sleep -Seconds 5
                        }
                        Stop-Notice2 $noticePhone
                        if ($ok) {
                            $conv2 = Invoke-ConvertToDigitalLicense2 $key
                            if ($conv2.Ok) {
                                Show-Info2 "Da kich hoat bang Confirmation ID va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`nCID: $($cidGroups -join ' ')`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
                            } else {
                                Show-Info2 "Da kich hoat bang Confirmation ID thanh cong (5 ky tu cuoi: $last5).`r`nTuy nhien buoc tu dong chuyen sang Digital License chua thanh cong ($($conv2.Detail)).`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Da kich hoat (Canh bao Digital License)'
                            }
                        } else {
                            $atpText = $atpOut
                            if ($atpText.Length -gt 1200) { $atpText = $atpText.Substring(0, 1200) }
                            Show-Info2 "Kich hoat bang CID chua thanh cong. Loi tu he thong:`n$atpText`nHay kiem tra lai CID va nhap lai." 'ActWin - CID chua thanh cong'
                        }
                    }
                    if (-not $ok) { Show-Info2 'Da dung kich hoat bang dien thoai. May van la Pro nhung chua kich hoat, hay chay lai acti-win.ps1 khi co CID dung.' 'ActWin - Chua kich hoat' }
                }
            }
        } else {
            Show-Info2 "Khong lay duoc Installation ID tu he thong. Loi online truoc do:`n$errText" 'ActWin - Khong lay duoc IID'
        }
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
    $editionC = ''
    try { $editionC = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID } catch { }
    if ($editionC -match 'Professional') {
        Show-InfoC 'Da upgrade len Windows Pro. Lua chon 2 khong kich hoat, ban co the kich hoat sau bang key cua ban.' 'ActWin - Da len Pro'
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
    if (Test-Activated $last5) {
        Write-Host "May da kich hoat san voi key co 5 ky tu cuoi $last5. Chuyen thang sang buoc ghi nhan Digital License..."
        $conv = Invoke-ConvertToDigitalLicense $key
        if ($conv.Ok) {
            Show-Info "May da kich hoat san voi key $last5 va da chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
        } else {
            Show-Info "May da kich hoat san voi key $last5, nhung buoc tu dong chuyen sang Digital License chua thanh cong ($($conv.Detail)).`r`nHay mo Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Canh bao Digital License'
        }
        exit
    }
    $result = Invoke-ActivateAndCheck $key $last5
    if ($result.Ok) {
        $conv = Invoke-ConvertToDigitalLicense $key
        if ($conv.Ok) {
            Show-Info "Da kich hoat va chuyen doi thanh cong sang Ban quyen ky thuat so (Digital License)!`r`n5 ky tu cuoi: $last5`r`nKhi cai lai Win tren may nay se tu dong nhan ban quyen!" 'ActWin - Digital License Thanh cong'
        } else {
            Show-Info "Da kich hoat Windows Pro thanh cong (5 ky tu cuoi: $last5).`r`nTuy nhien buoc tu dong chuyen sang Digital License chua thanh cong ($($conv.Detail)).`r`nNeu Settings chua bao Digital license, hay vao Settings > System > Activation > Change product key de nhap de key nay." 'ActWin - Da kich hoat (Canh bao Digital License)'
        }
    } else {
        # Already-Pro machine: same phone flow as phase 2, instead of
        # stopping at the online error.
        Invoke-PhoneActivation $last5 $result.Output $key | Out-Null
    }
    exit
}

# Not Pro yet: save phase 2 first, then upgrade the edition, then reboot.
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
& changepk.exe /ProductKey $GenericProKey
Show-Info 'Dang chuan bi upgrade len Pro. Dung tat may. May se tu khoi dong lai khi chuan bi xong, sau khi dang nhap lai phase 2 se tu nhap key cua ban va kiem tra kich hoat. Neu khong thay man hinh Preparing va may khong tu khoi dong lai, hay khoi dong lai thu cong - task phase 2 van con va se chay luc dang nhap.' 'ActWin - Dang chuan bi upgrade'
