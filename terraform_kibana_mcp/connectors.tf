locals {
  # Load all JSON files from the connectors folder
  connector_files = fileset("${path.module}/connectors", "*.json")
  
  # Decode each JSON file into a map
  connectors_raw = {
    for f in local.connector_files :
    f => jsondecode(file("${path.module}/connectors/${f}"))
  }

  # Build a safe, non-sensitive boolean map of which connectors have tokens
  has_token = {
    for k, v in local.connectors_raw : k => nonsensitive(contains(keys(var.mcp_bearer_tokens), v.name))
  }

  connectors_with_tokens = {
    for k, v in local.connectors_raw : k => v if local.has_token[k] == true
  }

  connectors_without_tokens = {
    for k, v in local.connectors_raw : k => v if local.has_token[k] == false
  }
}

resource "terraform_data" "connector_hash" {
  for_each = local.connectors_raw
  input    = md5(jsonencode(each.value))
}

# Connectors WITH tokens (sensitive config)
resource "elasticstack_kibana_action_connector" "connector_sensitive" {
  for_each = local.connectors_with_tokens

  name              = each.value.name
  connector_type_id = each.value.connector_type_id
  
  config = can(each.value.config) ? jsonencode(
    merge(
      each.value.config,
      {
        headers = merge(
          can(each.value.config.headers) ? each.value.config.headers : {},
          { "Authorization" = "Bearer ${var.mcp_bearer_tokens[each.value.name]}" }
        )
      }
    )
  ) : null
  
  secrets = can(each.value.secrets) ? jsonencode(each.value.secrets) : null
  space_id = can(each.value.space_id) ? each.value.space_id : "default"

  lifecycle {
    replace_triggered_by = [
      terraform_data.connector_hash[each.key]
    ]
  }
}

# Connectors WITHOUT tokens (non-sensitive config)
resource "elasticstack_kibana_action_connector" "connector" {
  for_each = local.connectors_without_tokens

  name              = each.value.name
  connector_type_id = each.value.connector_type_id
  
  config = can(each.value.config) ? jsonencode(each.value.config) : null
  
  secrets = can(each.value.secrets) ? jsonencode(each.value.secrets) : null
  space_id = can(each.value.space_id) ? each.value.space_id : "default"

  lifecycle {
    replace_triggered_by = [
      terraform_data.connector_hash[each.key]
    ]
    # Workaround: the elasticstack provider injects extra fields (__tf_provider_context, hasAuth)
    # into .config after apply, causing "inconsistent values for sensitive attribute" errors.
    ignore_changes = [config]
  }
}

