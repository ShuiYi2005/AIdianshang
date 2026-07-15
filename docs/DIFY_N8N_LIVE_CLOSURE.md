# Dify and n8n live closure

## Current local state

- Dify has an unpublished Chatflow named AI20 Customer Service Chatflow.
- Dify has two registered custom API tools: db-simulator and agent-service-rag.
  They expose only read-only order, product, logistics, and approved
  knowledge-search operations.
- n8n has the published workflow AI20 Local Customer Support. Its production
  entry is POST /webhook/ai20/customer-support.

## Runtime contract

1. A commerce platform posts a customer event to the n8n production Webhook.
2. n8n maps body fields, preserves trace_id and idempotency_key, and calls
   agent-service over the Docker network.
3. With DIFY_APP_ENABLED=false, agent-service uses the local policy, RAG, and
   db-simulator boundary. This is the verified local fallback path.
4. With DIFY_APP_ENABLED=true, agent-service calls the published Dify App API
   and accepts only the structured response documented in
   prompts/support/dify-chatflow-system.md.
5. Dify may call only the two registered read-only tools. It never connects to
   PostgreSQL directly. Agent-service persists the response, audit records,
   cost metadata, and handoff state, then n8n returns the result to the
   commerce platform.

## Enable the Dify segment

The Dify segment is deliberately not enabled in the local environment because
the local Dify workspace has no configured model provider. To enable it:

1. Configure an approved model provider in Dify.
2. In the Chatflow LLM node, select that model, paste
   prompts/support/dify-chatflow-system.md, bind db-simulator and
   agent-service-rag, enable the documented JSON structured output, and
   publish the Chatflow.
3. Create an application API key in Dify Access API.
4. Store the following values only in the target environment:

    DIFY_APP_ENABLED=true
    DIFY_APP_API_URL=http://dify-api:5001/v1/chat-messages
    DIFY_APP_API_KEY=<Dify App API key>
    DIFY_APP_TIMEOUT_SECONDS=15

5. Redeploy agent-service, then invoke tests/services/verify_n8n_webhook.ps1.

If Dify is unavailable, lacks a key, or returns non-structured content,
agent-service creates a controlled human handoff instead of inventing facts.

## Deployment and verification

    powershell -ExecutionPolicy Bypass -File scripts/import-n8n-customer-support-workflow.ps1
    powershell -ExecutionPolicy Bypass -File scripts/verify.ps1

The import script is an ID-based n8n upsert, publishes the workflow, restarts
n8n so its production Webhook is loaded, and confirms the published version.
