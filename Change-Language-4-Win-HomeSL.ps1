[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Danh sach URL chua file thuc thi
$URLs = @(
    'https://raw.githubusercontent.com/milansavio/Savio/main/Change-Language-4-Win-HomeSL.bat'
)
# Tai noi dung tu URL
foreach ($URL in $URLs | Sort-Object { Get-Random }) {
    try {
        $response = Invoke-WebRequest -Uri $URL -UseBasicParsing
        break
    } catch {}
}
if (-not $response) {
    Write-Host "Failed to retrieve the script from the available repository, aborting!"
    return
}
# Tao file tam de luu noi dung script
$rand = [Guid]::NewGuid().Guid
$FilePath = "$env:USERPROFILE\AppData\Local\Temp\changelang_$rand.bat"
Set-Content -Path $FilePath -Value $response.Content
# Thuc thi file batch
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$FilePath`"" -Wait
# Xoa file tam sau khi thuc thi
Remove-Item -Path $FilePath -Force
