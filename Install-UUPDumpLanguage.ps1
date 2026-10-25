param(
    [Parameter(Mandatory = $true)]
    [string]$Language
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Exit codes: 0 = da cai dat xong (LXP), 2 = chi tai duoc file ESD, can convert sang CAB roi cai tay, 1 = loi.
function Test-LxpInstalled {
    param([string]$Lang)
    $key = $Lang.Replace('-', '').ToLower()
    $found = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*LanguageExperiencePack*' -and
        ($_.Name.Replace('-', '').Replace('.', '').ToLower() -like "*$key*")
    }
    return ($null -ne $found)
}

function Test-FileHash {
    param($Path, $ExpectedSha256)
    if (-not $ExpectedSha256) { return $true }
    $hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
    return ($hash -eq $ExpectedSha256.ToLower())
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

    $fullBuild = $null
    if ($null -ne $reg.UBR) {
        try { $fullBuild = [version]"$buildNumber.$($reg.UBR)" } catch { $fullBuild = $null }
    }

    Write-Host "Dang tim ban Windows cho build $buildNumber ($arch) tren UUPDump..."
    $list = Invoke-RestMethod -Uri "https://api.uupdump.net/listid.php?search=$buildNumber" -UseBasicParsing
    $candidates = @()
    foreach ($prop in $list.response.builds.PSObject.Properties) {
        $b = $prop.Value
        if ($b.arch -ne $arch) { continue }
        # Win10 dung tieu de "Feature update to Windows ...".
        # Win11 25H2/26H2 tro di dung tieu de tran "Windows 11, version XXHY (build)".
        # Ca hai dang deu la ban GA; cac dang Insider/CPC/Azure khong khop hai mau nay.
        if ($b.title -like 'Feature update to Windows*' -or $b.title -like 'Windows 1*, version *') {
            $candidates += $b
        }
    }
    if ($candidates.Count -eq 0) {
        Write-Host "Khong tim thay ban Windows GA cho build $buildNumber ($arch) tren UUPDump."
        exit 1
    }
    if ($null -ne $fullBuild) {
        $fitting = @()
        foreach ($b in $candidates) {
            try {
                if ([version]$b.build -le $fullBuild) { $fitting += $b }
            } catch { }
        }
        if ($fitting.Count -gt 0) { $candidates = $fitting }
    }
    $selected = $candidates | Sort-Object { [long]$_.created } -Descending | Select-Object -First 1
    Write-Host "Chon ban: $($selected.title)"

    $info = Invoke-RestMethod -Uri "https://api.uupdump.net/get.php?id=$($selected.uuid)" -UseBasicParsing
    $files = $info.response.files

    # Truong hop 1: LXP (Win10 moi ngon ngu, Win11 cac ngon ngu partial nhu hi-IN).
    $wantLxp = "LanguageExperiencePack.$Language.Neutral.appx"
    $lxpEntry = $null
    $lxpName = $null
    foreach ($prop in $files.PSObject.Properties) {
        if ($prop.Name.ToLower() -eq $wantLxp.ToLower()) {
            $lxpEntry = $prop.Value
            $lxpName = $prop.Name
            break
        }
    }
    if ($null -ne $lxpEntry) {
        $outFile = Join-Path $env:TEMP $lxpName
        $sizeMB = [math]::Round([double]$lxpEntry.size / 1MB, 1)
        Write-Host "Dang tai $lxpName ($sizeMB MB)..."
        Invoke-WebRequest -Uri $lxpEntry.url -OutFile $outFile -UseBasicParsing
        if (-not (Test-FileHash -Path $outFile -ExpectedSha256 $lxpEntry.sha256)) {
            Write-Host "Sai checksum, file tai ve co the bi loi."
            Remove-Item $outFile -Force -ErrorAction SilentlyContinue
            exit 1
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
    }

    # Truong hop 2: LP dang ESD (Win11 26H2 cac ngon ngu full nhu vi-VN khong co LXP).
    # DISM chi cai duoc file CAB, khong cai truc tiep file ESD, nen tool chi tai ve
    # va bao duong dan de nguoi dung convert sang CAB (wimlib/ADK) roi cai tay.
    $langEsc = [regex]::Escape($Language)
    $esdPattern = "(?i)^Microsoft-Windows-Client-LanguagePack-Package[-_].*[-_]$langEsc\.esd$"
    $esdEntry = $null
    $esdName = $null
    foreach ($prop in $files.PSObject.Properties) {
        if ($prop.Name -match $esdPattern) {
            $esdEntry = $prop.Value
            $esdName = $prop.Name
            break
        }
    }
    if ($null -ne $esdEntry) {
        $outFile = Join-Path $env:TEMP $esdName
        $sizeMB = [math]::Round([double]$esdEntry.size / 1MB, 1)
        Write-Host "Ban Windows nay chi cung cap goi ngon ngu dang ESD, khong co LXP."
        Write-Host "Dang tai $esdName ($sizeMB MB)..."
        Invoke-WebRequest -Uri $esdEntry.url -OutFile $outFile -UseBasicParsing
        if (-not (Test-FileHash -Path $outFile -ExpectedSha256 $esdEntry.sha256)) {
            Write-Host "Sai checksum, file tai ve co the bi loi."
            Remove-Item $outFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Write-Host "Da tai goi ngon ngu ve: $outFile"
        Write-Host "DISM khong cai truc tiep file ESD. Hay convert file nay sang CAB (bang wimlib hoac ADK) roi chay: dism /online /add-package /packagepath:<file>.cab"
        exit 2
    }

    Write-Host "Khong tim thay goi ngon ngu cho $Language trong ban nay (ca LXP va LP ESD)."
    exit 1
} catch {
    Write-Host "Loi UUPDump: $($_.Exception.Message)"
    exit 1
}
