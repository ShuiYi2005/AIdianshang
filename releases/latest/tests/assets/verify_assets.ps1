$ErrorActionPreference = "Stop"

$requiredPaths = @(
    "config/app.example.yaml",
    "config/app.local.yaml",
    "config/customer-service/handoff-rules.yaml",
    "config/customer-service/risk-keywords.yaml",
    "config/customer-service/faq-routing.yaml",
    "prompts/support/customer-service-system.md",
    "prompts/shared/handoff-policy.md",
    "knowledge/support/after-sales-policy.md",
    "knowledge/support/faq.md",
    "workflows/n8n/customer-service-simulated-flow.md",
    "specs/workflows/n8n-simulated-customer-service.yaml",
    "docs/INDUSTRY_STANDARD_TARGET_ARCHITECTURE.md",
    "docs/PRODUCTION_READINESS_DESIGN.md",
    "docs/PRODUCTIZATION_EXECUTION_PLAN.md",
    "evaluations/customer-service-smoke.json",
    "specs/services/agent-service.yaml",
    "specs/services/api-management.yaml",
    "specs/adapters/commerce-adapter.yaml",
    "specs/adapters/crm-adapter.yaml",
    "specs/rag/rag-system.yaml",
    "specs/monitoring/evaluation-system.yaml",
    "specs/security/access-control.yaml",
    "specs/security/data-masking.yaml",
    "specs/data/retention-policy.yaml",
    "specs/tenancy/multi-tenant-isolation.yaml",
    "specs/tools/tool-resilience.yaml",
    "specs/operations/sync-and-release.yaml",
    "specs/support/agent-workbench.yaml",
    "dify-assets/README.md"
)

foreach ($path in $requiredPaths) {
    if (!(Test-Path -LiteralPath $path)) {
        throw "Missing required asset: $path"
    }
}

$handoff = Get-Content -Raw -LiteralPath "config/customer-service/handoff-rules.yaml"
if ($handoff -notmatch "human_handoff") {
    throw "handoff-rules.yaml must include human_handoff action"
}

$systemPrompt = Get-Content -Raw -LiteralPath "prompts/support/customer-service-system.md"
if ($systemPrompt -notmatch "NO_FABRICATION") {
    throw "customer-service-system.md must include no-fabrication policy marker"
}

"OK repository assets verified"
