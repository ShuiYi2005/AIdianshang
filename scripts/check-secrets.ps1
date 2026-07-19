param(
    [string[]]$Paths = @("deployment", "docs", "specs", "config", "scripts", "README.md", "AGENTS.md")
)

$ErrorActionPreference = "Stop"

# These are machine-local runtime credentials and are intentionally ignored by
# Git. Scan the complete deployment tree, but never treat those local files as
# release artifacts.
$ignoredRuntimeFiles = @(
    (Join-Path (Get-Location) "deployment\\.env"),
    (Join-Path (Get-Location) "deployment\\env\\local.env")
) | ForEach-Object { [System.IO.Path]::GetFullPath($_) }

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
    $files = $files | Where-Object {
        $resolvedPath = (Resolve-Path -LiteralPath $_.FullName).Path
        $resolvedPath -ne $selfPath -and $resolvedPath -notin $ignoredRuntimeFiles
    }

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
