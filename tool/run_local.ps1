$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$jdk = Join-Path $root ".tools\jdk"
if (Test-Path $jdk) {
  $home = Get-ChildItem $jdk -Directory | Select-Object -First 1
  if ($null -ne $home) {
    $env:JAVA_HOME = $home.FullName
    $env:Path = "$($home.FullName)\bin;" + $env:Path
  }
}

Write-Host "IntroNews local: http://localhost:8080"
Write-Host "Emulator UI: http://127.0.0.1:4000"
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
  Write-Host "Java가 없으면 Firestore/Storage 에뮬레이터가 시작되지 않습니다."
}

npm install --prefix functions
npm install
Start-Process -FilePath "npm" -ArgumentList "run","emulators" -WorkingDirectory $root
flutter run -d web-server --web-hostname localhost --web-port 8080 --dart-define=USE_EMULATORS=true
