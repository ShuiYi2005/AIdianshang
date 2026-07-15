param(
    [string]$EnvFile = "deployment/env/local.env"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $EnvFile)) {
    throw "Env file not found: $EnvFile"
}

$required = @(
    "APP_ENV",
    "POSTGRES_PASSWORD",
    "DIFY_SECRET_KEY",
    "DIFY_INIT_PASSWORD",
    "DIFY_INNER_API_KEY",
    "PLUGIN_SERVER_KEY",
    "N8N_ENCRYPTION_KEY",
    "BUSINESS_DB_USER",
    "BUSINESS_DB_PASSWORD",
    "BUSINESS_DB_NAME"
)

$values = @{}
Get-Content -LiteralPath $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if (!$line -or $line.StartsWith("#")) {
        return
    }
    $parts = $line.Split("=", 2)
    if ($parts.Count -eq 2) {
        $values[$parts[0]] = $parts[1]
    }
}

foreach ($key in $required) {
    if (!$values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
        throw "Missing required env var: $key"
    }
}

$difyEnabled = $values.ContainsKey("DIFY_APP_ENABLED") -and $values["DIFY_APP_ENABLED"].ToLowerInvariant() -in @("1", "true", "yes", "on")
if ($difyEnabled) {
    foreach ($key in @("DIFY_APP_API_URL", "DIFY_APP_API_KEY", "DIFY_APP_TIMEOUT_SECONDS")) {
        if (!$values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
            throw "Missing required Dify app env var when DIFY_APP_ENABLED=true: $key"
        }
    }
}

$weakValues = @("change-me", "replace-with-secret-manager-value", "password", "secret")
if ($values["APP_ENV"] -in @("staging", "prod")) {
    foreach ($key in $required) {
        if ($weakValues -contains $values[$key]) {
            throw "Weak placeholder value is not allowed for $($values["APP_ENV"]): $key"
        }
    }
    if ($difyEnabled -and $weakValues -contains $values["DIFY_APP_API_KEY"]) {
        throw "Weak placeholder value is not allowed for $($values["APP_ENV"]): DIFY_APP_API_KEY"
    }
}

"OK env file verified: $EnvFile"
