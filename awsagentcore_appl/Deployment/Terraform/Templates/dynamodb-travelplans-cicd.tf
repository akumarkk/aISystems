terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change to your preferred region
}

resource "aws_dynamodb_table" "travel_plans" {
  name         = "TravelPlans"
  billing_mode = "PAY_PER_REQUEST" # On-demand capacity
  hash_key     = "City"
  range_key    = "Duration"

  # Primary Key Attributes
  attribute {
    name = "City"
    type = "S" # String
  }

  attribute {
    name = "Duration"
    type = "N" # Number (e.g., number of days)
  }

  # Non-key attributes (TravelPlan, VacationCost) must NOT be declared here;
  # DynamoDB rejects attributes not used by a key or index.

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = "production"
    Application = "TravelPlanner"
  }
}

output "table_name" {
  value       = aws_dynamodb_table.travel_plans.name
  description = "The name of the DynamoDB table."
}

output "table_arn" {
  value       = aws_dynamodb_table.travel_plans.arn
  description = "The ARN of the DynamoDB table."
}