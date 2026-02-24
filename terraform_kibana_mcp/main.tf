terraform {
  required_version = ">= 1.0.0"

  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.11"
    }
    restapi = {
      source  = "mastercard/restapi"
      version = "~> 1.18"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "elasticstack" {
  elasticsearch {
    # Replace with your cluster coordinates and API key, or use environment variables
    # ELASTICSEARCH_ENDPOINTS and ELASTICSEARCH_API_KEY
    endpoints = [var.elasticsearch_endpoint]
    api_key   = var.elasticsearch_api_key
  }
  kibana {
    # Replace with your Kibana coordinates
    # KIBANA_ENDPOINTS and KIBANA_API_KEY
    endpoints = [var.kibana_endpoint]
    api_key   = var.kibana_api_key
  }
}

provider "restapi" {
  uri                  = var.kibana_endpoint
  write_returns_object = true
  debug                = true

  headers = {
    "Authorization" = "ApiKey ${var.kibana_api_key}"
    "kbn-xsrf"      = "true"
    "Content-Type"  = "application/json"
    "x-elastic-internal-origin" = "Kibana"
    "kbn-version"   = "9.4.0"
  }
}
