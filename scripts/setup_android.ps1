# One-time Android setup for SAIBAAN Connect.
# Prerequisites: Flutter (stable), Android Studio/SDK, Node.js 20, Firebase CLI
# (npm i -g firebase-tools), FlutterFire CLI (dart pub global activate flutterfire_cli).
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File scripts/setup_android.ps1 -FirebaseProject <project-id>

param(
  [Parameter(Mandatory = $true)][string]$FirebaseProject
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\mobile')

# 1. Generate the remaining Android platform files. Existing files
#    (AndroidManifest.xml, MainActivity.kt) are kept.
flutter create . --platforms=android --org com.saibaan --project-name saibaan_connect

# 2. Firebase plugins and local_auth need minSdk 23.
$gradle = Get-ChildItem android/app -Filter 'build.gradle*' | Select-Object -First 1
$content = Get-Content $gradle.FullName -Raw
$content = $content -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
$content = $content -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
Set-Content -Path $gradle.FullName -Value $content -Encoding utf8
Write-Host "Set minSdk 23 in $($gradle.Name)"

# 3. Connect to Firebase (writes android/app/google-services.json, which is git-ignored).
flutterfire configure --project=$FirebaseProject --platforms=android --yes

flutter pub get
Write-Host ''
Write-Host 'Done. Next:'
Write-Host '  cd backend/functions; npm install; npm run deploy'
Write-Host '  firebase deploy --only firestore,storage'
Write-Host '  Register the first admin in the app, then: npm run bootstrap-admin -- <email> <project-id>'
