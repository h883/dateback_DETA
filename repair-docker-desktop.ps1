# Run from an elevated PowerShell window:
#   powershell -ExecutionPolicy Bypass -File .\repair-docker-desktop.ps1

$ErrorActionPreference = "Stop"

$dockerRunDir = Join-Path $env:LOCALAPPDATA "Docker\run"
$backupDir = Join-Path $env:LOCALAPPDATA ("Docker\run.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Host "Stopping Docker Desktop and WSL related processes..."
Get-Process | Where-Object { $_.ProcessName -match "Docker|com\.docker" } | Stop-Process -Force -ErrorAction SilentlyContinue
wsl --shutdown 2>$null

Write-Host "Stopping WSL services..."
Stop-Service -Name WslService -Force -ErrorAction SilentlyContinue
Stop-Service -Name LxssManager -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

if (Test-Path -LiteralPath $dockerRunDir) {
    Write-Host "Moving Docker run directory:"
    Write-Host "  $dockerRunDir"
    Write-Host "to:"
    Write-Host "  $backupDir"
    Move-Item -LiteralPath $dockerRunDir -Destination $backupDir -Force
}

Write-Host "Creating a clean Docker run directory..."
New-Item -ItemType Directory -Path $dockerRunDir -Force | Out-Null

Write-Host "Restarting WSL services..."
Start-Service -Name WslService -ErrorAction SilentlyContinue
Start-Service -Name LxssManager -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Start Docker Desktop again."
