# Runs SAIBAAN Connect fully on this PC: Firebase emulators + demo data + app in Chrome.
#
#   powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1 -NoApp     # backend only
#   powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1 -Test      # backend + end-to-end tests
#
# Emulator UI (browse the database, users, files): http://localhost:4000
# Demo logins: admin@ / hr@ / manager@ / supervisor@ / employee@saibaan.demo — password Demo@12345
# Data lives in memory and is reset every time the emulators restart.

param([switch]$NoApp, [switch]$Test)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')

# Tool locations (installed by winget / npm / git clone).
$jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($jdk) { $env:JAVA_HOME = $jdk.FullName; $env:Path = "$($jdk.FullName)\bin;$env:Path" }
$env:Path = "C:\Program Files\nodejs;$env:APPDATA\npm;C:\src\flutter\bin;$env:Path"

Write-Host '==> Building Cloud Functions'
Push-Location "$root\backend\functions"
if (-not (Test-Path node_modules)) { npm install --no-fund --no-audit }
npm run build
Pop-Location

Write-Host '==> Starting Firebase emulators in a new window'
Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$root'; firebase emulators:start --project demo-saibaan" | Out-Null

Write-Host -NoNewline '==> Waiting for emulators'
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline) {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:5001/demo-saibaan/asia-south1/resolveLoginEmail' -Method Post `
      -ContentType 'application/json' -Body '{"data":{"phone":"03000000001"}}' -TimeoutSec 3 | Out-Null
    break
  } catch {
    if ($_.Exception.Response) { break }  # functions answered (even with an error)
    Write-Host -NoNewline '.'; Start-Sleep -Seconds 2
  }
}
Write-Host ''

Write-Host '==> Loading demo data'
Push-Location "$root\backend\functions"
node tools/seed-emulator.js
if ($Test) { node tools/e2e-emulator.js }
Pop-Location

if (-not $NoApp) {
  Write-Host '==> Launching the app in Chrome (press q in this window to stop)'
  Set-Location "$root\mobile"
  flutter run -d chrome --web-port 8686 --dart-define=USE_EMULATOR=true
}
