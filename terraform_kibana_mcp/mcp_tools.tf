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

# Create tools via a shell script that checks the JSON payload for failures and retries.
# The restapi_object cannot do this as it only checks for an HTTP 200 OK status.
resource "null_resource" "bulk_create_mcp_tools" {
  for_each = local.mcp_tools_by_namespace

  triggers = {
    tools_hash    = md5(jsonencode(each.value))
    connector_id  = try(elasticstack_kibana_action_connector.connector_sensitive["${each.key}_mcp.json"].connector_id, elasticstack_kibana_action_connector.connector["${each.key}_mcp.json"].connector_id)
    namespace     = each.key
  }

  provisioner "local-exec" {
    command = <<-EOT
      NAMESPACE="${self.triggers.namespace}"
      CONNECTOR_ID="${self.triggers.connector_id}"
      
      PAYLOAD=$(cat <<JSONEOF
{"connector_id":"$CONNECTOR_ID","tools":$(cat "${path.module}/mcp_tools/$${NAMESPACE}.json"),"namespace":"$NAMESPACE","tags":[],"skip_existing":true}
JSONEOF
)

      MAX_RETRIES=12
      for i in $(seq 1 $MAX_RETRIES); do
        echo "[$NAMESPACE] Attempt $i/$MAX_RETRIES: Creating tools..."
        RESPONSE=$(curl -s -X POST \
          -H "Authorization: ApiKey ${var.kibana_api_key}" \
          -H "kbn-xsrf: true" \
          -H "Content-Type: application/json" \
          -H "x-elastic-internal-origin: Kibana" \
          -H "kbn-version: 9.4.0" \
          "${var.kibana_endpoint}/internal/agent_builder/tools/_bulk_create_mcp" \
          -d "$PAYLOAD")
          
        FAILED=$(echo "$RESPONSE" | grep -o '"failed":[0-9]*' | head -1 | cut -d: -f2)
        
        if [ "$FAILED" = "0" ] || [ -z "$FAILED" ]; then
          echo "[$NAMESPACE] All tools created successfully."
          exit 0
        fi
        
        echo "[$NAMESPACE] $FAILED tools failed. Retrying in 15 seconds..."
        sleep 15
      done
      
      echo "[$NAMESPACE] ERROR: Tools still failing after $MAX_RETRIES attempts."
      echo "Last response: $RESPONSE"
      exit 1
    EOT
    interpreter = ["/bin/sh", "-c"]
  }
  
  depends_on = [
    null_resource.delete_existing_tools
  ]
}
