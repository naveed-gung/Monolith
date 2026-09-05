# Patches the vendored phosphor_flutter 2.1.0 copy for Flutter >= 3.44, where
# IconData is a final class and can no longer be subclassed outside the SDK.
#
# What it does (idempotent — safe to re-run):
#   1. Rewrites every generated icon constant:
#        PhosphorFlatIconData(0xXXXX, 'Style')
#          -> IconData(0xXXXX, fontFamily: 'PhosphorStyle',
#                      fontPackage: 'phosphor_flutter', matchTextDirection: true)
#        PhosphorDuotoneIconData(0xYYYY, PhosphorIconData(0xXXXX, 'Duotone'))
#          -> IconData(0xYYYY, fontFamily: 'PhosphorDuotone',
#                      fontPackage: 'phosphor_flutter', matchTextDirection: true)
#      (duotone constants lose their secondary layer; see phosphor_icon_data.dart)
#   2. Reports any leftover old-constructor references outside the shim file.
#
# Run from anywhere:  powershell -NoProfile -ExecutionPolicy Bypass -File apply_flutter344_patch.ps1

$ErrorActionPreference = 'Stop'
$srcDir = Join-Path $PSScriptRoot 'lib\src'

$files = Get-ChildItem $srcDir -Filter 'phosphor_icons_*.dart'
if (-not $files) { throw "No generated icon files found under $srcDir" }

$total = 0
foreach ($f in $files) {
  $c = [IO.File]::ReadAllText($f.FullName)
  $before = $c
  $c = [regex]::Replace(
    $c,
    "PhosphorFlatIconData\((0x[0-9A-Fa-f]+),\s*'([A-Za-z]+)'\)",
    'IconData($1, fontFamily: ''Phosphor$2'', fontPackage: ''phosphor_flutter'', matchTextDirection: true)')
  $c = [regex]::Replace(
    $c,
    "PhosphorDuotoneIconData\(\s*(0x[0-9A-Fa-f]+),\s*PhosphorIconData\((0x[0-9A-Fa-f]+),\s*'Duotone'\)\s*,?\s*\)",
    'IconData($1, fontFamily: ''PhosphorDuotone'', fontPackage: ''phosphor_flutter'', matchTextDirection: true)')
  if ($c -ne $before) {
    [IO.File]::WriteAllText($f.FullName, $c, [Text.UTF8Encoding]::new($false))
    $n = ([regex]::Matches($before, 'PhosphorFlatIconData\(|PhosphorDuotoneIconData\(')).Count
    Write-Host ("patched: {0} ({1} sites)" -f $f.Name, $n)
    $total += $n
  }
}
Write-Host ("Total constructor sites rewritten: {0}" -f $total)

$leftovers = Get-ChildItem $srcDir -Filter '*.dart' |
  Where-Object { $_.Name -ne 'phosphor_icon_data.dart' } |
  Select-String -Pattern 'PhosphorFlatIconData\(|PhosphorDuotoneIconData\(|PhosphorIconData\('
if ($leftovers) {
  Write-Host 'REMAINING old-constructor references outside shim:'
  $leftovers | Group-Object Filename | ForEach-Object {
    Write-Host ("  {0}: {1} lines" -f $_.Name, $_.Count)
  }
  exit 1
}
else {
  Write-Host 'Remaining old-constructor references outside shim: 0'
}
