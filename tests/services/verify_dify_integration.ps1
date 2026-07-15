param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

Push-Location "services/agent-service"
try {
    python -m unittest test_dify_client.py
    if ($LASTEXITCODE -ne 0) {
        throw "Dify client unit tests failed"
    }
} finally {
    Pop-Location
}

$compose = docker compose --env-file $EnvFile -f $ComposeFile config
foreach ($setting in @("DIFY_APP_ENABLED", "DIFY_APP_API_URL", "DIFY_APP_API_KEY", "DIFY_APP_TIMEOUT_SECONDS")) {
    if (([string]::Join([Environment]::NewLine, $compose)) -notmatch $setting) {
        throw "agent-service compose configuration is missing $setting"
    }
}

$prompt = Get-Content -Raw -LiteralPath "prompts/support/dify-chatflow-system.md"
foreach ($field in @("reply", "handoff_required", "handoff_reason", "used_tool", "used_knowledge")) {
    if ($prompt -notmatch $field) {
        throw "Dify prompt is missing structured result field: $field"
    }
}

"OK Dify integration boundary verified"
