$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$patterns = @(
  "[cC][oO][dD][eE][xX]",
  "[sS][tT][eE][aA][mM][dD][iI][sS][pP][lL][aA][yY]",
  "vulkan\.[cC][oO][dD][eE][xX]",
  "[gG][aA][mM][iI][nN][gG]_compositor",
  "[gG][aA][mM][iI][nN][gG]-compositor"
)

foreach ($pattern in $patterns) {
  $matches = & rg -n -i $pattern $Root
  if ($LASTEXITCODE -eq 0) {
    Write-Host "found pattern: $pattern" -ForegroundColor Red
    $matches | Out-Host
    exit 1
  }
}

Write-Host "public_name_check=pass"
