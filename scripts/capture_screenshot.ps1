param([Parameter(Mandatory=$true)][ValidateSet('library','songs','player','downloads','search','settings')][string]$Name)
$monolithAdb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$monolithScreenshotDir = Join-Path $PSScriptRoot '../docs/screenshots'
& $monolithAdb shell screencap -p "/sdcard/monolith-$Name.png"
if ($LASTEXITCODE -ne 0) { throw 'Screenshot capture failed' }
& $monolithAdb pull "/sdcard/monolith-$Name.png" (Join-Path $monolithScreenshotDir "$Name.png")
if ($LASTEXITCODE -ne 0) { throw 'Screenshot copy failed' }
