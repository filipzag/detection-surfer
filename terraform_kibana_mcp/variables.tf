variable "elasticsearch_endpoint" {
  description = "Elasticsearch API endpoint"
  type        = string
}

variable "elasticsearch_api_key" {
  description = "Elasticsearch API Key"
  type        = string
  sensitive   = true
}

variable "kibana_endpoint" {
  description = "Kibana API endpoint"
  type        = string
}

variable "kibana_api_key" {
  description = "Kibana API Key"
  type        = string
  sensitive   = true
}

variable "ai_agent_api_path" {
  description = "The Kibana API path to POST AI agents from Agent Builder (e.g., /api/agent_builder/agents)"
  type        = string
  default     = "/api/agent_builder/agents"
}

variable "mcp_bearer_tokens" {
  description = "A map of MCP connector names to their respective Bearer Auth tokens"
  type        = map(string)
  default     = {}
  sensitive   = true
}
