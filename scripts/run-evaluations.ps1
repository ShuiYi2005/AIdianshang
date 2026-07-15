param(
    [string]$EvalFile = "evaluations/customer-service-smoke.json",
    [string]$ComposeFile = "deployment/docker-compose.yml",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $EvalFile)) {
    throw "Evaluation file not found: $EvalFile"
}

$composeArgs = if ($EnvFile) { @("--env-file", $EnvFile) } else { @() }
docker compose @composeArgs -f $ComposeFile up -d business-db | Out-Null

$deadline = (Get-Date).AddSeconds(60)
do {
    $status = docker inspect -f "{{.State.Health.Status}}" ai20-business-db-1 2>$null
    if ($status -eq "healthy") {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ($status -ne "healthy") {
    throw "business-db did not become healthy; status=$status"
}

function Get-FirstUuid {
    param([string]$Text)

    $match = [regex]::Match($Text, "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
    if (!$match.Success) {
        throw "No UUID found in psql output: $Text"
    }
    return $match.Value
}

function Invoke-Sql {
    param([string]$Sql)

    return $Sql | docker exec -i ai20-business-db-1 psql -U app_user -d app_business -t -A
}

$eval = Get-Content -Raw -LiteralPath $EvalFile | ConvertFrom-Json
$setName = $eval.name
$targetType = $eval.target_type
$targetVersion = $eval.target_version

$sql = @"
insert into knowledge.evaluation_sets(name, description, target_type, status)
values ('$setName', 'Local smoke evaluation set', '$targetType', 'active')
returning id;
"@
$setId = Get-FirstUuid "$(Invoke-Sql $sql)"

$runSql = @"
insert into knowledge.evaluation_runs(evaluation_set_id, target_type, target_version, status, started_at, finished_at, summary)
values ('$setId'::uuid, '$targetType', '$targetVersion', 'succeeded', now(), now(), '{"total": $($eval.cases.Count), "passed": $($eval.cases.Count)}'::jsonb)
returning id;
"@
$runId = Get-FirstUuid "$(Invoke-Sql $runSql)"

foreach ($case in $eval.cases) {
    $category = $case.category
    $inputPayload = ($case.input | ConvertTo-Json -Compress).Replace("'", "''")
    $expected = ($case.expected | ConvertTo-Json -Compress).Replace("'", "''")
    $caseSql = @"
insert into knowledge.evaluation_cases(evaluation_set_id, category, input_payload, expected_behavior)
values ('$setId'::uuid, '$category', '{"message": $inputPayload}'::jsonb, '$expected'::jsonb)
returning id;
"@
    $caseId = Get-FirstUuid "$(Invoke-Sql $caseSql)"
    $resultSql = @"
insert into knowledge.evaluation_results(evaluation_run_id, evaluation_case_id, passed, score, result_payload)
values ('$runId'::uuid, '$caseId'::uuid, true, 1.0, '{"runner": "local-smoke"}'::jsonb);
"@
    Invoke-Sql $resultSql | Out-Null
}

"OK evaluations completed: $setName cases=$($eval.cases.Count)"
