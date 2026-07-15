# Dify + n8n Live Closure Design

## Goal

Turn the existing local customer-service vertical slice into an executable request path:

```text
simulated e-commerce event
  -> n8n webhook
  -> agent-service
  -> Dify Chatflow
  -> approved HTTP tools
  -> db-simulator / business-db
  -> Dify structured response
  -> agent-service audit and persistence
  -> n8n webhook response
```

The implementation keeps business decisions in `services/`, orchestration in
`workflows/`, prompts in `prompts/`, and deployment-only configuration in
`deployment/`. Dify and n8n platform source remains untouched.

## Scope and Acceptance

1. A versioned Dify Chatflow definition and an operator runbook exist in the
   repository. The Chatflow returns a JSON object with `reply`,
   `handoff_required`, `handoff_reason`, `used_tool`, and `used_knowledge`.
2. Dify custom tools use OpenAPI contracts for `db-simulator` read APIs and the
   narrow `agent-service` RAG API. No Dify tool connects to PostgreSQL directly.
3. `agent-service` calls Dify's Chat API only when
   `DIFY_APP_ENABLED=true` and an application API key is injected. It validates
   and records the result, then retains the existing deterministic local path as
   a safe local-development fallback when Dify is explicitly disabled.
4. The n8n workflow is importable, has no secrets in JSON, can be activated with
   the n8n CLI, and forwards a webhook request to `agent-service`.
5. Automated checks cover the Dify configuration boundary, active n8n workflow,
   and the webhook-to-agent contract. Existing Docker Compose and core HTTP
   checks remain green.

## Preconditions and External Boundary

The current Dify instance has one administrator account but no model-provider
credential, no published application, and no application API key. A real
Chatflow cannot produce an LLM response until an operator supplies one of:

- a provider API key configured in Dify; or
- a reachable OpenAI-compatible model endpoint configured in Dify.

The repository must never store the provider key, Dify application API key, or
administrator password. Creating/publishing the Dify app is therefore an
operator action documented and made reproducible through versioned assets. No
direct manipulation of Dify's internal PostgreSQL tables is permitted.

## Service Boundaries

### n8n

n8n receives an external platform event, normalizes the message envelope,
forwards it to `agent-service`, and returns the result. It does not decide
intent, query business tables, call a model, or store a secret in the workflow
JSON.

### agent-service

`agent-service` remains the trusted product boundary. It establishes trace and
idempotency context, applies policy, calls Dify, validates a structured answer,
writes context/audit/cost records, and creates a human-handoff task when
required. It is the only component called by n8n.

### Dify

Dify owns LLM orchestration: intent interpretation, approved tool selection,
and compliant response drafting. It is called through `POST /v1/chat-messages`
with server-side credentials only. Dify must return JSON, not platform-specific
payloads.

### Tools and database

`db-simulator` is the only Dify-visible source of real-time order/product/
logistics facts in this local environment. It queries `business-db` through its
own service boundary. The `agent-service` RAG endpoint is exposed as a narrow,
read-only tool. Tools return controlled JSON and have timeouts; database
connections, passwords, and internal tables are not exposed to Dify.

## Contracts

### External webhook -> n8n

```json
{
  "conversation_id": "channel-conversation-id",
  "customer_id": "channel-customer-id",
  "user_message": "Please check ORD-DBTEST",
  "platform": "simulated-ecommerce",
  "role": "support_agent",
  "trace_id": "optional-channel-trace",
  "idempotency_key": "platform-event-id"
}
```

### agent-service -> Dify

`agent-service` sends `query`, stable `user`, and limited non-PII `inputs`.
Order, product, and logistics facts are retrieved by Dify only through an
approved tool. The app API key is sent in `Authorization`, never in a request
body, log, workflow JSON, or response.

### Dify -> agent-service

The Dify final answer is parsed as the following JSON object. Unknown fields
are ignored; invalid JSON is treated as an unstructured answer and never
interpreted as a policy decision.

```json
{
  "reply": "Customer-facing response",
  "handoff_required": false,
  "handoff_reason": "",
  "used_tool": true,
  "used_knowledge": false
}
```

### agent-service -> n8n -> platform

The existing reply envelope remains stable and adds explicit execution metadata:
`model_provider`, `model_name`, and `dify_conversation_id`. All user-facing
fields remain masked according to the caller role.

## Dify Chatflow Shape

The configured flow uses the following node responsibilities:

1. Start: accept `query`, `conversation_id`, `customer_id`, `platform`, and
   `role`.
2. Intent/policy LLM: classify the inquiry; never invent order or logistics
   facts.
3. Conditional branches: order, product, logistics, knowledge, and escalation.
4. HTTP/custom-tool nodes: call only the approved read-only OpenAPI operations.
5. Final LLM: synthesize tool/knowledge output into the strict final JSON
   contract.
6. End: return the final JSON text as `answer`.

Prompt source text is maintained under `prompts/`; the Dify console references
the same policy, rather than being the only copy of critical instructions.

## Failure, Rollback, and Observability

- Dify disabled: retain the existing local deterministic response behavior.
- Dify unavailable or malformed output: create a controlled handoff response;
  do not silently fabricate a business fact.
- Tool unavailable: Dify reports the limitation and requests handoff; the
  agent-service records the outcome and tool/audit metadata.
- n8n failure: its execution log retains the trace ID; the external caller gets
  a bounded HTTP failure rather than a partial duplicate response.
- Rollback: set `DIFY_APP_ENABLED=false`, redeploy only `agent-service`, and
  deactivate the imported n8n workflow if necessary. No schema migration is
  required by this change.

## Verification

1. Static check: the OpenAPI and Dify assets contain no secrets and expose only
   approved operations.
2. Unit/integration check: a fake Dify response verifies parsing, structured
   response use, malformed-output fallback, and no-key fallback.
3. n8n check: import the workflow with `--activeState=fromJson`, publish it,
   and assert that its active webhook responds through `agent-service`.
4. Docker check: run `scripts/verify.ps1` plus the new closure verification.
5. Live Dify check after model configuration: submit a known order query and
   confirm Dify tool use, masked response, context snapshot, audit logs, and
   n8n response share one trace ID.
