![Detection Surfer](images/det_surfer.jpg)

# Detection Surfer

An autonomous detection engineering agent for Elastic Security, powered by Kibana AI and a fleet of MCP connectors.

## What Is This?

Detection Surfer deploys a fully-configured AI agent — **Detection Surfer** — inside your Elastic Security cluster via Terraform. The agent operates as a senior detection engineer: it researches threats, drafts and validates EQL rules, runs Atomic Red Team tests, and pushes production-ready rules to GitHub — autonomously.

### The Agent

Detection Surfer is a Kibana AI agent model connected to five MCP (Model Context Protocol) servers. It follows a strict, tool-sequenced workflow:

1. **Threat research** — queries MITRE ATT&CK® for TTPs, groups, and detection gaps using `mitre.*` tools  
2. **Schema discovery** — inspects live index mappings via `platform.core.*` before writing any query  
3. **Detection drafting** — writes EQL-first, stateful (sequence-based) rules using 100% ECS fields  
4. **Atomic validation** — syncs with a fork of Atomic Red Team, runs or creates a test, then validates it  
5. **Deployment** — creates a TOML rule in the `ai-detections` GitHub repo on a feature branch, creates a Pull Request, and enables the rule on the live cluster via `elastic_rules.*`

The agent is forbidden from pushing directly to `main`. Every rule goes through a PR with test evidence attached.

### The Tools (MCP Connectors)

| Connector | Namespace | Purpose |
|---|---|---|
| `mitre_mcp` | `mitre.*` | MITRE ATT&CK® intel — techniques, groups, coverage gaps |
| `detections_mcp` | `detections.*` | Query your existing detection library — find, compare, suggest |
| `elastic_rules_mcp` | `elastic_rules.*` | Create, enable, disable, and list rules on the live cluster |
| `art_mcp` | `art.*` | Atomic Red Team — refresh, execute, validate tests |
| `github_mcp` | `github.*` | Branch, commit, PR, and code search on GitHub |

---

## Quick Start

### Prerequisites

- Terraform ≥ 1.0
- An Elastic Cloud deployment (Kibana + Elasticsearch) with an API key
- GitHub PAT with repo scope (for the GitHub MCP)
- MCP servers running and reachable (see each connector's JSON in `connectors/`)
  > **Need to host the MCPs?** You can easily deploy the entire suite of required MCP servers using the unified Docker compose setup in the [MCP-tools-deploy](https://github.com/filipzag/MCP-tools-deploy) repository.

### 1. Configure variables

```bash
cd terraform_kibana_mcp
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your endpoints, API keys, and MCP bearer tokens:

```hcl
kibana_endpoint       = "https://your-project.kb.region.aws.elastic.cloud"
kibana_api_key        = "your-kibana-api-key"
elasticsearch_endpoint = "https://your-project.es.region.aws.elastic.cloud"
elasticsearch_api_key  = "your-es-api-key"

mcp_bearer_tokens = {
  "art_mcp.json"          = "your-art-token"
  "github_mcp.json"       = "your-github-token"
  "detections_mcp.json"   = "your-detections-token"
  "elastic_rules_mcp.json" = "your-elastic-rules-token"
  "mitre_mcp.json"        = "your-mitre-token"
}
```

### 2. Deploy

```bash
terraform init
terraform apply
```

> **Note:** If some tools fail on the first apply (MCP servers may need time to initialize), run `terraform apply` a second time — it idempotently picks up any missing tools.

### 3. Use the agent

Open Kibana → AI Assistant → select the **Detection Surfer** agent. Give it a threat, CVE, or MITRE technique and it will start autonomously.

---

## Destroy

```bash
terraform destroy
```

All tools and connectors are cleanly removed from Kibana.

---

## Structure

```
terraform_kibana_mcp/
├── connectors/          # MCP connector JSON configs
├── mcp_tools/           # Tool definitions per namespace
├── ai_agents/           # Agent config + instructions
├── connectors.tf        # Kibana connector resources
├── mcp_tools.tf         # Tool creation + cleanup
├── ai_agents.tf         # Agent resource
├── main.tf              # Provider config
├── variables.tf         # Input variables
└── terraform.tfvars     # Your secrets (git-ignored)
```
