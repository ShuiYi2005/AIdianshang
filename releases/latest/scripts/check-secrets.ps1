param(
    [string[]]$Paths = @("deployment/docker-compose.yml", "docs", "specs", "config", "scripts", "README.md", "AGENTS.md")
)

$ErrorActionPreference = "Stop"

$knownSecrets = @(
    "dify_password_123",
    "admin123",
    "sk-9f83b7c2e1d4a5b6c7d8e9f0a1b2c3d4",
    "n8n-enc-key-1234567890",
    "app_business_password_123"
)

$hits = @()
foreach ($path in $Paths) {
    if (!(Test-Path -LiteralPath $path)) {
        continue
    }
    $files = @()
    $item = Get-Item -LiteralPath $path
    if ($item.PSIsContainer) {
        $files = Get-ChildItem -LiteralPath $path -Recurse -File
    } else {
        $files = @($item)
    }
    $selfPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
    $files = $files | Where-Object { (Resolve-Path -LiteralPath $_.FullName).Path -ne $selfPath }

    foreach ($secret in $knownSecrets) {
        $matches = $files | Select-String -Pattern ([regex]::Escape($secret)) -ErrorAction SilentlyContinue
        if ($matches) {
            $hits += $matches
        }
    }
}

if ($hits.Count -gt 0) {
    $hits | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line)" }
    throw "Known secret literals found outside ignored env/runtime files"
}

"OK no known secret literals found"
