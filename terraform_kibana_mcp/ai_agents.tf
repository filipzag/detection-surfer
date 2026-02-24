locals {
  # Load all JSON files from the ai_agents folder
  ai_agent_files = fileset("${path.module}/ai_agents", "*.json")
  
  # Decode each JSON file into a map
  raw_ai_agents = {
    for f in local.ai_agent_files :
    f => jsondecode(file("${path.module}/ai_agents/${f}"))
  }

  ai_agents = {
    for f, agent in local.raw_ai_agents : f => merge(
      agent,
      can(agent.configuration.instructions_file) ? {
        configuration = merge(
          { for k, v in agent.configuration : k => v if k != "instructions_file" },
          {
            instructions = file("${path.module}/ai_agents/${agent.configuration.instructions_file}")
          }
        )
      } : {}
    )
  }
}

# Wait for tools to be fully indexed before creating the agent
resource "time_sleep" "wait_for_tools" {
  depends_on = [
    restapi_object.bulk_create_mcp_tools
  ]

  create_duration = "30s"
}

# Uses the restapi provider to POST the AI agents to Kibana
# Since official Terraform resources for these might not exist yet
resource "restapi_object" "ai_agent" {
  for_each = local.ai_agents

  path         = var.ai_agent_api_path
  data         = jsonencode({ for k, v in each.value : k => v if !contains(["readonly", "type"], k) })
  update_data  = jsonencode({ for k, v in each.value : k => v if !contains(["readonly", "type", "id"], k) })
  
  # The attribute in the API response that represents the ID of the agent
  id_attribute = "id" 

  depends_on = [
    time_sleep.wait_for_tools
  ]
}
