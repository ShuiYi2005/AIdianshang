# Platform Engineering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize environment configuration, verification, repository-managed assets, and the next business-service integration path.

**Architecture:** Keep Dify/n8n as platform services and keep business logic in `services/`. Use layered environment files under `deployment/env/`, versioned non-secret configuration under `config/`, and repeatable PowerShell verification scripts.

**Tech Stack:** Docker Compose, PowerShell, PostgreSQL, FastAPI, Dify, n8n, Redis, Weaviate.

---

### Task 1: Environment Layout

**Files:**
- Create: `deployment/env/local.env.example`
- Create: `deployment/env/dev.env.example`
- Create: `deployment/env/staging.env.example`
- Create: `deployment/env/prod.env.example`
- Modify: `deployment/docker-compose.yml`
- Modify: `README.md`

- [ ] Add environment example files with required variable names.
- [ ] Keep `deployment/.env` compatibility.
- [ ] Document local command using `--env-file deployment/env/local.env`.
- [ ] Run `docker compose --env-file deployment/env/local.env -f deployment/docker-compose.yml config`.

### Task 2: Configuration Files

**Files:**
- Create: `config/app.example.yaml`
- Create: `config/app.local.yaml`
- Create: `config/customer-service/handoff-rules.yaml`
- Create: `config/customer-service/risk-keywords.yaml`
- Create: `config/customer-service/faq-routing.yaml`

- [ ] Add non-secret application configuration.
- [ ] Add customer support rules as YAML.
- [ ] Keep secrets out of YAML.

### Task 3: Verification Scripts

**Files:**
- Create: `scripts/check-env.ps1`
- Create: `scripts/check-secrets.ps1`
- Create: `scripts/verify.ps1`

- [ ] `check-env.ps1` verifies required variables.
- [ ] `check-secrets.ps1` scans Compose and docs for known demo literals.
- [ ] `verify.ps1` runs compose config, HTTP checks, business schema check, and worker Redis check.

### Task 4: Asset Directories

**Files:**
- Create: `dify-assets/README.md`
- Create: `dify-assets/apps/README.md`
- Create: `dify-assets/tools/README.md`
- Create: `dify-assets/datasets/README.md`
- Create: `knowledge/README.md`
- Create: `prompts/support/customer-service-system.md`
- Create: `prompts/shared/handoff-policy.md`
- Create: `workflows/n8n/README.md`

- [ ] Add repository-managed asset directories.
- [ ] Add current prompt and handoff policy placeholders based on existing project rules.
- [ ] Do not invent real platform export content.

### Task 5: Documentation Cleanup

**Files:**
- Rewrite: `docs/SECURITY.md`
- Rewrite: `docs/DATA_ARCHITECTURE.md`
- Rewrite: `docs/DATABASE_SCHEMA.md`
- Modify: `docs/CHECKLIST.md`
- Modify: `docs/PLAYBOOK.md`

- [ ] Ensure documents are valid UTF-8 Chinese.
- [ ] Add verification commands.
- [ ] Add environment layering rules.

### Task 6: Final Verification

**Files:**
- Test: `scripts/verify.ps1`
- Test: `tests/database/verify_business_schema.ps1`

- [ ] Run full verification.
- [ ] Report remaining gaps.
