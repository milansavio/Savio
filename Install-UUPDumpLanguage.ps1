param(
    [Parameter(Mandatory = $true)]
    [string]$Language
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-LxpInstalled {
    param([string]$Lang)
    $key = $Lang.Replace('-', '').ToLower()
    $found = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*LanguageExperiencePack*' -and
        ($_.Name.Replace('-', '').Replace('.', '').ToLower() -like "*$key*")
    }
    return ($null -ne $found)
}

try {
    if (Test-LxpInstalled -Lang $Language) {
        Write-Host "Goi LXP cho $Language da duoc cai san."
        exit 0
    }

    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildNumber = $reg.CurrentBuildNumber
    $archRaw = $env:PROCESSOR_ARCHITECTURE
    if ($archRaw -eq 'AMD64') { $arch = 'amd64' }
    elseif ($archRaw -eq 'ARM64') { $arch = 'arm64' }
    elseif ($archRaw -eq 'x86') { $arch = 'x86' }
    else { $arch = $archRaw.ToLower() }

    Write-Host "Dang tim ban Feature update cho build $buildNumber ($arch) tren UUPDump..."
    $list = Invoke-RestMethod -Uri "https://api.uupdump.net/listid.php?search=$buildNumber" -UseBasicParsing
    $candidates = @()
    foreach ($prop in $list.response.builds.PSObject.Properties) {
        $b = $prop.Value
        if ($b.title -like 'Feature update to Windows*' -and $b.arch -eq $arch) {
            $candidates += $b
        }
    }
    if ($candidates.Count -eq 0) {
        Write-Host "Khong tim thay ban Feature update cho build $buildNumber ($arch) tren UUPDump."
        exit 1
    }
    $selected = $candidates | Sort-Object { [long]$_.created } -Descending | Select-Object -First 1
    Write-Host "Chon ban: $($selected.title)"

    $info = Invoke-RestMethod -Uri "https://api.uupdump.net/get.php?id=$($selected.uuid)" -UseBasicParsing
    $want = "LanguageExperiencePack.$Language.Neutral.appx"
    $entry = $null
    $entryName = $null
    foreach ($prop in $info.response.files.PSObject.Properties) {
        if ($prop.Name.ToLower() -eq $want.ToLower()) {
            $entry = $prop.Value
            $entryName = $prop.Name
            break
        }
    }
    if ($null -eq $entry) {
        Write-Host "Khong tim thay goi LXP cho $Language trong ban nay."
        exit 1
    }

    $outFile = Join-Path $env:TEMP $entryName
    $sizeMB = [math]::Round([double]$entry.size / 1MB, 1)
    Write-Host "Dang tai $entryName ($sizeMB MB)..."
    Invoke-WebRequest -Uri $entry.url -OutFile $outFile -UseBasicParsing

    if ($entry.sha256) {
        $hash = (Get-FileHash -Path $outFile -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $entry.sha256.ToLower()) {
            Write-Host "Sai checksum, file tai ve co the bi loi."
            Remove-Item $outFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }

    Write-Host "Dang cai dat goi ngon ngu..."
    Add-AppxPackage -Path $outFile

    if (Test-LxpInstalled -Lang $Language) {
        Write-Host "Cai dat goi ngon ngu tu UUPDump thanh cong."
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        exit 0
    }
    Write-Host "Khong xac nhan duoc goi LXP da cai dat."
    exit 1
} catch {
    Write-Host "Loi UUPDump: $($_.Exception.Message)"
    exit 1
}
