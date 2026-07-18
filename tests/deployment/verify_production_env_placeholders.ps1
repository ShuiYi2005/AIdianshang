$ErrorActionPreference = "Stop"

$tempFile = Join-Path ([IO.Path]::GetTempPath()) ("ai20-release-env-" + [guid]::NewGuid().ToString("N") + ".env")

try {
    Copy-Item -LiteralPath "deployment/env/release.env.example" -Destination $tempFile
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & powershell -ExecutionPolicy Bypass -File scripts/check-env.ps1 -EnvFile $tempFile 2>$null
    $checkExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference

    if ($checkExitCode -eq 0) {
        throw "production environment validation accepted template placeholder secrets"
    }
}
finally {
    if (Test-Path -LiteralPath $tempFile) { Remove-Item -Force -LiteralPath $tempFile }
}

"OK production placeholder rejection verified"
