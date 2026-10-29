terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region of the Cognito user pool"
}

variable "user_pool_id" {
  type        = string
  default     = "us-east-1_igFfZFLDL"
  description = "Existing Cognito user pool (User pool - ybt67r)"
}

variable "resource_server_identifier" {
  type        = string
  default     = "vacation-planner"
  description = "Cognito resource server identifier. Full scope = <identifier>/<agent>_read|write"
}

variable "agents" {
  type = set(string)
  default = [
    "travel_research_expert",
    "local_expert__city_guide",
    "itinerary_planner",
    "travel_cost_optimizer",
    "quality_control_specialist_for",
  ]
  description = "Agent names from vac_planner/crew.jsonc. One app client and one read/write scope pair is created per agent."
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = "TravelPlanner"
      Environment = "production"
    }
  }
}

locals {
  # Custom scopes: <agent>_read and <agent>_write
  scopes = {
    for agent in var.agents : agent => {
      read  = "${agent}_read"
      write = "${agent}_write"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. Resource server holding the custom scopes of every agent
# -----------------------------------------------------------------------------
resource "aws_cognito_resource_server" "agents" {
  user_pool_id = var.user_pool_id
  identifier   = var.resource_server_identifier
  name         = "Vacation planner agents"

  dynamic "scope" {
    for_each = flatten([
      for agent, s in local.scopes : [
        { name = s.read, description = "Read access for ${agent}" },
        { name = s.write, description = "Write access for ${agent}" },
      ]
    ])

    content {
      scope_name        = scope.value.name
      scope_description = scope.value.description
    }
  }
}

# -----------------------------------------------------------------------------
# 2. One confidential app client per agent (client credentials), limited to its own scopes
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "agent" {
  for_each = var.agents

  name         = "${each.key}-client"
  user_pool_id = var.user_pool_id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.agents.identifier}/${local.scopes[each.key].read}",
    "${aws_cognito_resource_server.agents.identifier}/${local.scopes[each.key].write}",
  ]

  supported_identity_providers = ["COGNITO"]

  access_token_validity = 60
  token_validity_units {
    access_token = "minutes"
  }

  prevent_user_existence_errors = "ENABLED"
}

# -----------------------------------------------------------------------------
# 3. Outputs
# -----------------------------------------------------------------------------
output "client_ids" {
  value       = { for agent, c in aws_cognito_user_pool_client.agent : agent => c.id }
  description = "App client ID per agent. Use as jwt_allowed_clients on the AgentCore Gateway."
}

output "client_secrets" {
  value       = { for agent, c in aws_cognito_user_pool_client.agent : agent => c.client_secret }
  sensitive   = true
  description = "App client secret per agent (terraform output -json client_secrets)"
}

output "scopes" {
  value = {
    for agent, s in local.scopes : agent => [
      "${var.resource_server_identifier}/${s.read}",
      "${var.resource_server_identifier}/${s.write}",
    ]
  }
  description = "Full scope strings per agent, as requested in the token call"
}
