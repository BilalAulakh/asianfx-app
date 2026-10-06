# Builds a signed release APK for the website and prints what to enter in
# Admin > App Update.
#
# Usage (from the project folder):   powershell -ExecutionPolicy Bypass -File .\RELEASE_APK.ps1
#
# Before running: raise "version:" in pubspec.yaml, e.g. 1.0.1+2 -> 1.0.2+3
# (the number after + must go up every release).

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$site = Join-Path $root '..\fxasian-website\public'

if (-not (Test-Path (Join-Path $root 'android\key.properties'))) {
    throw 'android\key.properties is missing: the APK would not be signed with your release key, so phones would refuse the update.'
}

$line = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)\+(\d+)' | Select-Object -First 1
if (-not $line) { throw 'Could not read "version: x.y.z+N" from pubspec.yaml' }
$versionName = $line.Matches[0].Groups[1].Value
$buildNumber = $line.Matches[0].Groups[2].Value

Write-Host "Building FXAsian $versionName (build $buildNumber)..." -ForegroundColor Cyan
Push-Location $root
try { flutter build apk --release } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path $site) {
    Copy-Item $apk (Join-Path $site 'FXAsian.apk') -Force
    Write-Host "Copied to $site\FXAsian.apk" -ForegroundColor Green
} else {
    Write-Host "Website folder not found; upload this file yourself: $apk" -ForegroundColor Yellow
}

$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)

Write-Host ''
Write-Host '=== Enter these in Admin > App Update (after the website is deployed) ===' -ForegroundColor Cyan
Write-Host "Version:       $versionName"
Write-Host "Build number:  $buildNumber"
Write-Host "SHA-256:       $sha"
Write-Host "APK size:      $sizeMb MB"
