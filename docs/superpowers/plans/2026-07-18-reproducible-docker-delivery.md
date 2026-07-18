# Reproducible Docker Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make online GitHub clones and offline release bundles start the AI customer-service stack reproducibly.

**Architecture:** The base Compose file is the online source-build entry point, while the release override consumes versioned images only. Local bootstrap/start scripts own secret generation and migration sequencing. Release packaging owns every local service image and the target image tags.

**Tech Stack:** Docker Compose, PowerShell 5+, PostgreSQL migrations, existing PowerShell verification scripts.

## Global Constraints

- Do not modify `platform/` source code.
- Keep deployment files under `deployment/` and business services under `services/`.
- Never commit a generated environment file or runtime data.
- Run Docker Compose and core HTTP verification after changes.

---

### Task 1: Local clone bootstrap and start path

**Files:**
- Create: `scripts/bootstrap-local.ps1`
- Create: `scripts/start-local.ps1`
- Create: `tests/deployment/verify_local_bootstrap.ps1`
- Modify: `README.md`
- Modify: `docs/CONFIGURATION.md`
- Modify: `docs/OPERATIONS.md`

- [ ] Write an isolated-environment test that invokes bootstrap and asserts all required secret values differ from template placeholders.
- [ ] Run the test and confirm it fails because the bootstrap script is absent.
- [ ] Implement bootstrap with no-overwrite protection and cryptographically random URL-safe secrets; implement start with database, migration, then full-stack ordering.
- [ ] Document `powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1` as the new-clone command.
- [ ] Re-run the bootstrap test and Compose config validation.

### Task 2: Compose and offline release parity

**Files:**
- Modify: `deployment/docker-compose.yml`
- Modify: `deployment/docker-compose.release.yml`
- Modify: `deployment/env/release.env.example`
- Modify: `deployment/release-manifest.example.json`
- Modify: `scripts/package-release.ps1`
- Modify: `scripts/install-release.ps1`
- Modify: `tests/deployment/verify_release_package.ps1`
- Create: `tests/deployment/verify_github_clone_readiness.ps1`

- [ ] Write readiness assertions for public-image pull policy, pinned n8n, release frontend image and release build override.
- [ ] Run the assertions and confirm they fail against the current deployment files.
- [ ] Make the base Compose online-capable, pin n8n to `2.22.5`, and make local services build from tracked source.
- [ ] Extend release packaging, manifest and release overlay for versioned `ai20-support-console`; rewrite its copied release template to point every local image to the package version.
- [ ] Stage business-db and migration execution before full offline startup.
- [ ] Re-run readiness and release-package verification.

### Task 3: End-to-end evidence

**Files:**
- Modify only if validation reveals a defect.

- [ ] Run all deployment readiness checks with `deployment/env/local.env.example`.
- [ ] Run the support-console unit tests and production build.
- [ ] Run the existing complete Docker verification with the real ignored local environment file.
- [ ] Inspect the worktree diff and commit the completed implementation.
