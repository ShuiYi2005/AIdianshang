# Dify + n8n Live Closure Implementation Plan

**Goal:** Implement a reproducible local integration path from a simulated
e-commerce webhook through n8n, agent-service, Dify, approved tools, and back
to the webhook caller.

**Known prerequisite:** Dify currently has no model credential, no app, and no
app API key. The code and workflow can be built and verified now; actual Dify
Chatflow publication and model inference are completed after a model provider
is configured in the Dify console.

## 1. Add executable contracts and operator assets

- [ ] Add a Dify-compatible tool OpenAPI contract for the db-simulator and
  agent-service RAG endpoints.
- [ ] Add a versioned Chatflow definition/template and console import/publish
  runbook.
- [ ] Verify that assets contain no credential-like values and do not expose
  direct database operations.

## 2. Add the FastAPI Dify boundary using tests first

- [ ] Write a test that parses a valid structured Dify response and fails before
  the new client exists.
- [ ] Add a small `dify_client.py` responsible only for `/v1/chat-messages`.
- [ ] Update `agent-service` to use Dify only when explicitly enabled and
  configured; otherwise preserve the existing local path.
- [ ] Record model metadata in existing audit/cost records without persisting an
  application API key.
- [ ] Verify failure handling for timeout, non-2xx, and invalid structured
  result.

## 3. Make environment configuration explicit

- [ ] Add non-secret Dify application variables to Compose and safe env
  templates.
- [ ] Update environment validation and configuration documentation.
- [ ] Run Compose configuration validation before rebuilding any service.

## 4. Import and activate n8n workflow

- [ ] Update the versioned workflow to be activation-ready and retain only
  orchestration nodes.
- [ ] Add an idempotent PowerShell import/publish script using n8n CLI.
- [ ] Import the workflow into the current n8n instance, publish it, and verify
  the active webhook route calls agent-service.

## 5. Verify the vertical slice and record the remaining external gate

- [ ] Rebuild and start agent-service with Docker Compose.
- [ ] Run the existing full verification plus the new integration verifier.
- [ ] Test the active n8n webhook with a known order request.
- [ ] Confirm Dify app/model publication remains blocked only by absent provider
  credentials and app key, not by code or infrastructure.

## Rollback

Set `DIFY_APP_ENABLED=false`, run `docker compose up -d agent-service`, and
deactivate the n8n workflow by ID. The existing local agent path stays usable;
this plan introduces no database migration.
