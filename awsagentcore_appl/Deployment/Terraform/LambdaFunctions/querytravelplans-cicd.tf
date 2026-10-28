terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for deployment"
}

variable "table_name" {
  type        = string
  default     = "TravelPlans"
  description = "Target DynamoDB Table name"
}

variable "function_name" {
  type        = string
  default     = "query-travel-plans"
  description = "Name of the Lambda function"
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# 1. Existing DynamoDB Table Lookup
# -----------------------------------------------------------------------------
data "aws_dynamodb_table" "travel_plans" {
  name = var.table_name
}

# -----------------------------------------------------------------------------
# 2. Package Lambda Code from tools/vacation_store/query_travel_plans.py
# -----------------------------------------------------------------------------
data "archive_file" "query_travelplans_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../tools/vacation_store/query_travel_plans.py"
  output_path = "${path.module}/query_travel_plans.zip"
}

# -----------------------------------------------------------------------------
# 3. IAM Execution Role & Policies
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = "TravelPlanner"
    Environment = "production"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_query" {
  name = "DynamoDBQueryTravelPlansPolicy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:DescribeTable"
        ]
        Resource = data.aws_dynamodb_table.travel_plans.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 4. Lambda Function
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "query_travel_plans" {
  function_name    = var.function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "query_travel_plans.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.query_travelplans_zip.output_path
  source_code_hash = data.archive_file.query_travelplans_zip.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = data.aws_dynamodb_table.travel_plans.name
      LOG_LEVEL  = "INFO"
    }
  }

  tags = {
    Application = "TravelPlanner"
    Environment = "production"
  }
}

# -----------------------------------------------------------------------------
# 5. HTTPS Function URL (Enables direct HTTP GET/POST queries)
# -----------------------------------------------------------------------------
resource "aws_lambda_function_url" "query_travel_plans_url" {
  function_name      = aws_lambda_function.query_travel_plans.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["content-type"]
    max_age           = 300
  }
}

# -----------------------------------------------------------------------------
# 6. Outputs
# -----------------------------------------------------------------------------
output "function_name" {
  value       = aws_lambda_function.query_travel_plans.function_name
  description = "Name of the deployed Lambda function"
}

output "function_arn" {
  value       = aws_lambda_function.query_travel_plans.arn
  description = "ARN of the deployed Lambda function"
}

output "function_url" {
  value       = aws_lambda_function_url.query_travel_plans_url.function_url
  description = "Public HTTPS URL for querying travel plans directly"
}
