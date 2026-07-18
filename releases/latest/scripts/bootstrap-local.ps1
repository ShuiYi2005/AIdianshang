param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$TemplateFile = "deployment/env/local.env.example"
)

$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $EnvFile) {
    throw "Environment file already exists and will not be overwritten: $EnvFile"
}

if (!(Test-Path -LiteralPath $TemplateFile)) {
    throw "Environment template not found: $TemplateFile"
}

function New-LocalSecret {
    $bytes = New-Object byte[] 48
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return ([Convert]::ToBase64String($bytes).Replace("+", "").Replace("/", "").Replace("=", "").Substring(0, 48))
}

$secretKeys = @(
    "POSTGRES_PASSWORD",
    "DIFY_SECRET_KEY",
    "DIFY_INIT_PASSWORD",
    "DIFY_INNER_API_KEY",
    "PLUGIN_SERVER_KEY",
    "N8N_ENCRYPTION_KEY",
    "BUSINESS_DB_PASSWORD"
)

$secrets = @{}
foreach ($key in $secretKeys) {
    $secrets[$key] = New-LocalSecret
}

$output = foreach ($line in Get-Content -LiteralPath $TemplateFile) {
    $matchedKey = $secretKeys | Where-Object { $line -match "^$_=" } | Select-Object -First 1
    if ($matchedKey) {
        "$matchedKey=$($secrets[$matchedKey])"
    } else {
        $line
    }
}

$parent = Split-Path -Parent $EnvFile
if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

Set-Content -LiteralPath $EnvFile -Value $output -Encoding UTF8
"OK generated local environment file: $EnvFile"
