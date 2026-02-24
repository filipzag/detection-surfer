locals {
  # Load all JSON files from the mcp_tools folder
  tool_files = fileset("${path.module}/mcp_tools", "*.json")
  
  # Decode each JSON file into a map
  mcp_tools_by_namespace = {
    for f in local.tool_files :
    replace(f, ".json", "") => jsondecode(file("${path.module}/mcp_tools/${f}"))
  }
}

# Wait for MCP servers to become reachable after connectors are created
# This wait is CRITICAL because if tools are created too fast, the bulk create
# API will return success (HTTP 200) but fail internally to verify the tools,
# causing tools to silently fail to create.
resource "time_sleep" "wait_for_mcp_servers" {
  depends_on = [
    elasticstack_kibana_action_connector.connector_sensitive,
    elasticstack_kibana_action_connector.connector
  ]

  create_duration = "90s"
}

# Delete existing tools before (re)creating to prevent stale connector references
resource "null_resource" "delete_existing_tools" {
  for_each = local.mcp_tools_by_namespace

  triggers = {
    connector_id    = try(elasticstack_kibana_action_connector.connector_sensitive["${each.key}_mcp.json"].connector_id, elasticstack_kibana_action_connector.connector["${each.key}_mcp.json"].connector_id)
    tools_hash      = md5(jsonencode(each.value))
    tool_ids_json   = join(",", [for t in each.value : "\"${each.key}.${t.name}\""])
    kibana_endpoint = var.kibana_endpoint
    kibana_api_key  = var.kibana_api_key
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X POST \
        -H "Authorization: ApiKey ${self.triggers.kibana_api_key}" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -H "x-elastic-internal-origin: Kibana" \
        -H "kbn-version: 9.4.0" \
        "${self.triggers.kibana_endpoint}/internal/agent_builder/tools/_bulk_delete" \
        -d '{"ids": [${self.triggers.tool_ids_json}]}' || true
    EOT
  }

  # Also delete on destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      curl -s -X POST \
        -H "Authorization: ApiKey ${self.triggers.kibana_api_key}" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -H "x-elastic-internal-origin: Kibana" \
        -H "kbn-version: 9.4.0" \
        "${self.triggers.kibana_endpoint}/internal/agent_builder/tools/_bulk_delete" \
        -d '{"ids": [${self.triggers.tool_ids_json}]}'
    EOT
  }

  depends_on = [
    time_sleep.wait_for_mcp_servers
  ]
}

# Create tools via the REST API provider
resource "restapi_object" "bulk_create_mcp_tools" {
  for_each = local.mcp_tools_by_namespace

  path = "/internal/agent_builder/tools/_bulk_create_mcp"

  data = jsonencode({
    connector_id  = try(elasticstack_kibana_action_connector.connector_sensitive["${each.key}_mcp.json"].connector_id, elasticstack_kibana_action_connector.connector["${each.key}_mcp.json"].connector_id)
    tools         = each.value
    namespace     = each.key
    tags          = []
    skip_existing = true
  })

  id_attribute  = "results/0/toolId"
  create_method = "POST"
  
  depends_on = [
    null_resource.delete_existing_tools
  ]
}
