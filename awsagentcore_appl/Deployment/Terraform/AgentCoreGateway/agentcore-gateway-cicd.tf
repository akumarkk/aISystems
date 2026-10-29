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
  description = "AWS region for deployment"
}

variable "gateway_name" {
  type        = string
  default     = "vacation-planner-gateway"
  description = "Name of the AgentCore Gateway (letters, numbers and hyphens)"
}

variable "target_name" {
  type        = string
  default     = "query-travel-plans"
  description = "Gateway target name (letters, numbers and hyphens). Clients see tools as <target_name>___<tool name>."
}

variable "lambda_function_name" {
  type        = string
  default     = "query-travel-plans"
  description = "Existing Lambda function (deployed by Deployment/Terraform/LambdaFunctions) exposed as a gateway tool"
}

variable "jwt_discovery_url" {
  type        = string
  description = "OIDC discovery URL of the Cognito user pool, ending in /.well-known/openid-configuration"
}

variable "jwt_allowed_clients" {
  type        = list(string)
  default     = []
  description = "Cognito app client IDs allowed to call the gateway. Empty accepts any client of the issuer."
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

# -----------------------------------------------------------------------------
# 1. Tool definitions (tools/*.json) and the existing Lambda behind them
# -----------------------------------------------------------------------------
locals {
  query_travel_plans_tool = jsondecode(file("${path.module}/tools/query_travel_plans.json"))

  input_schema  = local.query_travel_plans_tool.inputSchema
  output_schema = local.query_travel_plans_tool.outputSchema

  input_required  = try(local.input_schema.required, [])
  output_required = try(local.output_schema.required, [])

  input_properties = [
    for name, p in local.input_schema.properties : {
      name        = name
      type        = p.type
      description = try(p.description, null)
      required    = contains(local.input_required, name)
    }
  ]

  output_properties = [
    for name, p in local.output_schema.properties : {
      name        = name
      type        = p.type
      description = try(p.description, null)
      required    = contains(local.output_required, name)
    }
  ]
}

data "aws_caller_identity" "current" {}

data "aws_lambda_function" "query_travel_plans" {
  function_name = var.lambda_function_name
}

# -----------------------------------------------------------------------------
# 2. Gateway service role (assumed by AgentCore, allowed to invoke the Lambda)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "gateway_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    # No aws:SourceArn condition: AgentCore rejected the gateway/* pattern when creating the target.
    # aws:SourceAccount still blocks cross-account confused-deputy use.
  }
}

resource "aws_iam_role" "gateway" {
  name               = "${var.gateway_name}-role"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume.json
}

data "aws_iam_policy_document" "gateway_lambda_invoke" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [data.aws_lambda_function.query_travel_plans.arn]
  }
}

resource "aws_iam_role_policy" "gateway_lambda_invoke" {
  name   = "InvokeQueryTravelPlansLambda"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway_lambda_invoke.json
}

# -----------------------------------------------------------------------------
# 3. AgentCore Gateway (MCP, Cognito JWT inbound auth)
# -----------------------------------------------------------------------------
resource "aws_bedrockagentcore_gateway" "this" {
  name            = var.gateway_name
  description     = "MCP gateway exposing vacation planner tools"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "CUSTOM_JWT"

  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url   = var.jwt_discovery_url
      allowed_clients = length(var.jwt_allowed_clients) > 0 ? toset(var.jwt_allowed_clients) : null
    }
  }

  depends_on = [aws_iam_role_policy.gateway_lambda_invoke]
}

# -----------------------------------------------------------------------------
# 4. Gateway target: the query_travel_plans tool backed by the Lambda
# -----------------------------------------------------------------------------
resource "aws_bedrockagentcore_gateway_target" "query_travel_plans" {
  name               = var.target_name
  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id
  description        = "Looks up saved vacation travel plans by destination city"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = data.aws_lambda_function.query_travel_plans.arn

        tool_schema {
          inline_payload {
            name        = local.query_travel_plans_tool.name
            description = local.query_travel_plans_tool.description

            input_schema {
              type        = local.input_schema.type
              description = try(local.input_schema.description, null)

              dynamic "property" {
                for_each = local.input_properties

                content {
                  name        = property.value.name
                  type        = property.value.type
                  description = property.value.description
                  required    = property.value.required
                }
              }
            }

            output_schema {
              type = local.output_schema.type

              dynamic "property" {
                for_each = local.output_properties

                content {
                  name        = property.value.name
                  type        = property.value.type
                  description = property.value.description
                  required    = property.value.required
                }
              }
            }
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# 5. Outputs (consumed by deploy_validate_agentcore_gateway.ps1)
# -----------------------------------------------------------------------------
output "gateway_id" {
  value       = aws_bedrockagentcore_gateway.this.gateway_id
  description = "AgentCore Gateway ID"
}

output "gateway_arn" {
  value       = aws_bedrockagentcore_gateway.this.gateway_arn
  description = "AgentCore Gateway ARN"
}

output "gateway_url" {
  value       = aws_bedrockagentcore_gateway.this.gateway_url
  description = "MCP endpoint of the gateway"
}

output "tool_name" {
  value       = "${aws_bedrockagentcore_gateway_target.query_travel_plans.name}___${local.query_travel_plans_tool.name}"
  description = "Tool name as listed by MCP tools/list (<target>___<tool>)"
}
