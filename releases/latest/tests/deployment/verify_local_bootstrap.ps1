param(
    [string]$TemplateFile = "deployment/env/local.env.example"
)

$ErrorActionPreference = "Stop"

function Read-EnvFile {
    param([string]$Path)

    $values = @{}
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (!$line -or $line.StartsWith("#")) { return }
        $parts = $line.Split("=", 2)
        if ($parts.Count -eq 2) { $values[$parts[0]] = $parts[1] }
    }
    return $values
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("ai20-bootstrap-" + [guid]::NewGuid().ToString("N"))
$envFile = Join-Path $tempRoot "local.env"

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    & powershell -ExecutionPolicy Bypass -File scripts/bootstrap-local.ps1 -EnvFile $envFile -TemplateFile $TemplateFile
    if ($LASTEXITCODE -ne 0) { throw "bootstrap-local.ps1 failed" }

    $values = Read-EnvFile -Path $envFile
    if ($values["APP_ENV"] -ne "local") { throw "bootstrap must preserve APP_ENV=local" }

    $secretKeys = @(
        "POSTGRES_PASSWORD",
        "DIFY_SECRET_KEY",
        "DIFY_INIT_PASSWORD",
        "DIFY_INNER_API_KEY",
        "PLUGIN_SERVER_KEY",
        "N8N_ENCRYPTION_KEY",
        "BUSINESS_DB_PASSWORD"
    )
    foreach ($key in $secretKeys) {
        $value = $values[$key]
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "change-me" -or $value.Length -lt 32) {
            throw "bootstrap did not generate a strong value for $key"
        }
    }

    $before = Get-Content -LiteralPath $envFile -Raw
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & powershell -ExecutionPolicy Bypass -File scripts/bootstrap-local.ps1 -EnvFile $envFile -TemplateFile $TemplateFile 2>$null
    $secondBootstrapExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($secondBootstrapExitCode -eq 0) { throw "bootstrap must not overwrite an existing environment file" }
    $after = Get-Content -LiteralPath $envFile -Raw
    if ($after -ne $before) { throw "bootstrap changed an existing environment file" }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -Recurse -Force -LiteralPath $tempRoot }
}

"OK local bootstrap verified"
