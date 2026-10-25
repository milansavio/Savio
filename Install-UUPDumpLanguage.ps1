param(
    [Parameter(Mandatory = $true)]
    [string]$Language
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Exit codes: 0 = da cai dat xong (Store LXP hoac UUPDump LXP), 2 = chi tai duoc file ESD, can convert sang CAB roi cai tay, 1 = loi.
# Thu tu fallback, tat ca deu tu dong, khong can nguoi dung thao tac tay:
#  1. Microsoft Store qua winget (goi LXP chinh thuc, khong phu thuoc build Windows).
#  2. UUPDump: goi LXP neu co (Win10 moi ngon ngu, Win11 cac ngon ngu partial nhu hi-IN).
#  3. UUPDump: goi LP dang ESD neu khong co LXP (Win11 26H2 cac ngon ngu full) -> chi tai ve, bao convert tay.

$storeIds = @{
    'vi-VN' = '9P0W68X0XZPT'
    'en-US' = '9PDSCC711RVF'
    'en-GB' = '9NT52VQ39BVN'
    'ja-JP' = '9N1W692FV4S1'
    'ko-KR' = '9N4TXPCVRNGF'
    'zh-CN' = '9NRMNT6GMZ70'
    'zh-TW' = '9PCJ4DHCQ1JQ'
    'fr-FR' = '9NHMG4BJKMDG'
    'de-DE' = '9P6CT0SLW589'
    'ru-RU' = '9NMJCX77QKPX'
    'es-ES' = '9NWVGWLHPB1Z'
    'pt-BR' = '9P8LBDM4FW35'
    'it-IT' = '9P8PQWNS6VJX'
    'th-TH' = '9MSTWFRL0LR4'
    'id-ID' = '9P4X3N4SDK8P'
    'hi-IN' = '9NZC3GRX8LD3'
}

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

    # Buoc 1: Microsoft Store qua winget.
    $productId = $storeIds[$Language]
    if ($null -ne $productId) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($null -ne $winget) {
            Write-Host "Dang thu cai goi ngon ngu $Language tu Microsoft Store (winget)..."
            try {
                winget install --id $productId --exact --source msstore --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Host "Winget bao loi: $($_.Exception.Message)"
            }
            if (Test-LxpInstalled -Lang $Language) {
                Write-Host "Cai dat goi ngon ngu tu Microsoft Store thanh cong."
                exit 0
            }
            Write-Host "Khong cai duoc qua Store, chuyen sang thu UUPDump..."
        } else {
            Write-Host "Khong tim thay winget, chuyen sang thu UUPDump..."
        }
    } else {
        Write-Host "Ngon ngu $Language chua co ma Store, chuyen sang thu UUPDump..."
    }

    # Buoc 2+3: UUPDump.
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
        # Win11 22H2 tro di dung tieu de tran "Windows 11, version XXHY (build)".
        # Win11 21H2 dung tieu de tran "Windows 11 (build)" hoac "Upgrade to Windows 11 (build)".
        # Cac dang tren deu la ban GA; cac dang Insider/CPC/Azure khong khop cac mau nay.
        if ($b.title -like 'Feature update to Windows*' -or $b.title -like 'Windows 1*, version *' -or $b.title -like 'Windows 11 (*' -or $b.title -like 'Upgrade to Windows 11*') {
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

    # Buoc 2: LXP tu UUPDump (Win10 moi ngon ngu, Win11 cac ngon ngu partial nhu hi-IN).
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

    # Buoc 3: LP dang ESD tu UUPDump (Win11 26H2 cac ngon ngu full khong co LXP).
    # DISM chi cai duoc file CAB, khong cai truc tiep file ESD, nen tool chi tai ve
    # va bao duong dan de nguoi dung convert sang CAB (wimlib/ADK) roi cai tay.
    # Ly do khong tu dong convert: file ESD nay khong phai 1 goi cai dat duy nhat ma la
    # toan bo kho WinSxS cua ngon ngu (464 file .mum/.cat + file .mui), khong the dong
    # thanh 1 file CAB de DISM cai duoc.
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
    Write-Host "Loi: $($_.Exception.Message)"
    exit 1
}
