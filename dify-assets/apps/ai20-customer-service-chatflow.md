# AI20 Customer Service Chatflow

## Local application

The local Dify workspace contains a Chatflow named AI20 Customer Service
Chatflow. It is intentionally not published until a model provider is
configured. Its public app API key must be injected only through
DIFY_APP_API_KEY.

## Graph

1. Start: receive `query` and the non-secret application inputs supplied by
   agent-service: `platform`, `role`, `trace_id`, and `conversation_id`.
2. Parameter Extractor: use `deepseek-chat` to classify the request as
   `order`, `product`, `logistics`, `order_by_logistics`, or `knowledge`, and
   extract the one required lookup value.
3. Conditional router: route each real-time intent to one read-only
   db-simulator operation; route all other requests to the approved knowledge
   search operation.
4. Tool nodes: invoke exactly one registered Tool, with retry and a bounded
   `tool_unavailable` fallback value.
5. Variable Aggregator: pass the selected Tool result into the response LLM.
6. LLM: use `deepseek-chat`, the content of
   `prompts/support/dify-chatflow-system.md`, and the strict structured-output
   schema below.
7. Direct Reply: map `{{#llm.text#}}` to the Dify App API answer. The
   agent-service validates this JSON and records the audited response.

The graph deliberately uses explicit Tool nodes instead of an unconstrained
Agent node. Dify 1.14 LLM nodes do not directly own Tool selection, and this
shape makes the permitted read path auditable and reproducible without a
Sandbox container.

The LLM node must enable structured output using this JSON schema:

    {
      "type": "object",
      "required": ["reply", "handoff_required", "handoff_reason", "used_tool", "used_knowledge"],
      "properties": {
        "reply": {"type": "string"},
        "handoff_required": {"type": "boolean"},
        "handoff_reason": {"type": "string"},
        "used_tool": {"type": "boolean"},
        "used_knowledge": {"type": "boolean"}
      }
    }

## Register custom tools

In Dify, open Tools and create/import custom OpenAPI tools from:

- http://db-simulator:8000/openapi.json
- http://agent-service:8010/openapi.json

The versioned source contracts are:

- dify-assets/tools/db-simulator.openapi.yaml
- dify-assets/tools/agent-service-rag.openapi.yaml

Only select `getOrder`, `getProduct`, `getLogistics`, `getOrderByLogistics`,
and `searchKnowledge`. Do not grant write operations or direct PostgreSQL
access.

## Publish and connect

1. Configure an LLM provider in Dify and select `deepseek-chat` in the
   Parameter Extractor and response LLM nodes.
2. Paste the prompt from prompts/support/dify-chatflow-system.md into the
   response LLM node.
3. Configure the five explicit read-only Tool nodes and enable structured
   output on the response LLM.
4. Run the Dify checklist with known order, product, logistics, knowledge, and
   handoff requests, then publish.
5. Create an app API key in Access API.
6. Set DIFY_APP_ENABLED=true and DIFY_APP_API_KEY only in the target
   environment, then redeploy agent-service.

The FastAPI integration rejects non-JSON Dify replies and creates a human
handoff when Dify or its app configuration is unavailable.
