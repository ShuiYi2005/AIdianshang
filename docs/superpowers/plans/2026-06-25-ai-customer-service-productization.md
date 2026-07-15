# AI Customer Service Productization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production-grade vertical slice for the AI customer service system.

**Architecture:** Add an `agent-service` as the productization control plane between workflow/Dify and tools. It owns request tracing, idempotency checks, masking, context snapshots, tool calls, fallback behavior, and audit writes while keeping CRM/ecommerce platform differences behind adapters.

**Tech Stack:** FastAPI, PostgreSQL, Redis-ready interfaces, Docker Compose, PowerShell verification scripts.

---

## Files

- Create `services/agent-service/`: FastAPI service for the productized agent boundary.
- Modify `deployment/docker-compose.yml`: add `agent-service`.
- Create `tests/services/verify_agent_service.ps1`: executable verification.
- Modify `scripts/verify.ps1`: include agent-service verification.
- Modify `tests/assets/verify_assets.ps1`: require productization docs/specs.

## Tasks

- [ ] Write `tests/services/verify_agent_service.ps1` and confirm it fails before the service exists.
- [ ] Implement `services/agent-service` with `/health`, `/metrics`, `/api/masking/preview`, and `/api/agent/reply`.
- [ ] Add Docker Compose service and environment wiring.
- [ ] Verify the agent can call `db-simulator`, save a context snapshot, write audit logs, and mask sensitive fields.
- [ ] Add evaluation runner skeleton and asset verification.
- [ ] Run full `scripts/verify.ps1`.
