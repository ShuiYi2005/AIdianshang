ALTER TABLE audit.tool_call_logs ADD COLUMN IF NOT EXISTS trace_id varchar(128);
ALTER TABLE audit.ai_response_logs ADD COLUMN IF NOT EXISTS trace_id varchar(128);

CREATE INDEX IF NOT EXISTS idx_tool_call_logs_trace_id ON audit.tool_call_logs(trace_id) WHERE trace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_response_logs_trace_id ON audit.ai_response_logs(trace_id) WHERE trace_id IS NOT NULL;
