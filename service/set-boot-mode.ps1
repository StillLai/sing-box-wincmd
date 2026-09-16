# Set WinSW service boot mode
# Usage: powershell -File set-boot-mode.ps1 -AutoXml <path> -ManualXml <path>
param(
    [string]$AutoXml,
    [string]$ManualXml
)

(Get-Content -Raw $AutoXml) -replace '<startmode>[^<]*</startmode>','<startmode>automatic</startmode>' | Set-Content -LiteralPath $AutoXml -Encoding UTF8
(Get-Content -Raw $ManualXml) -replace '<startmode>[^<]*</startmode>','<startmode>manual</startmode>' | Set-Content -LiteralPath $ManualXml -Encoding UTF8
