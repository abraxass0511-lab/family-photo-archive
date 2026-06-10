[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Photo Transfer Server"
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   Photo & Video Transfer Server" -ForegroundColor Yellow
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

# Wi-Fi IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^(127\.|169\.254)" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress
if (-not $ip) { $ip = "localhost" }
Write-Host "  Phone Access URL:" -ForegroundColor Green
Write-Host "  http://${ip}:8000/web/" -ForegroundColor White
Write-Host ""
Write-Host "  Close this window to stop the server." -ForegroundColor Gray
Write-Host ""

Set-Location "$PSScriptRoot\server"
& .\venv\Scripts\python.exe main.py
