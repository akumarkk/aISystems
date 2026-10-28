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
  region = "us-east-1" # Must match the region used in ../Templates
}

# The table is created by ../Templates (separate root module), so apply that first.
data "aws_dynamodb_table" "travel_plans" {
  name = "TravelPlans"
}

resource "aws_dynamodb_table_item" "item_1" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelPlan   = { S = "European Summer Getaway" }
    VacationCost = { N = "2500" }
    City         = { S = "Paris" }
    Duration     = { N = "7" }
  })
}

resource "aws_dynamodb_table_item" "item_2" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelPlan   = { S = "Tropical Beach Escape" }
    VacationCost = { N = "1800" }
    City         = { S = "Honolulu" }
    Duration     = { N = "5" }
  })
}