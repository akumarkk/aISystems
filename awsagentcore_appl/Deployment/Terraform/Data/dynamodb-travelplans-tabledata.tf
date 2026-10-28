terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
    TravelCity         = { S = "Paris" }
    Duration     = { N = "7" }
    origin = { S = "Seattle" }
    travel_dates = { S = "June 10-17, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$5,000" }
    interests    = { S = "food, hiking, history" }
    VacationCost = { N = "4500" }
    TravelPlan   = { S = "7-day Parisian cultural & culinary tour: Day 1 Eiffel Tower and Seine river dinner cruise; Day 2 Louvre Museum and Tuileries Garden; Day 3 Day hike in Fontainebleau Forest; Day 4 Montmartre food tasting and Sacre-Coeur; Day 5 Palace of Versailles royal estate tour; Day 6 Musee d'Orsay and Latin Quarter stroll; Day 7 Le Marais exploration and departure." }
  })
}

resource "aws_dynamodb_table_item" "item_2" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity         = { S = "Honolulu" }
    Duration     = { N = "5" }
    origin       = { S = "Seattle" }
    travel_dates = { S = "August 12-17, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$3,500" }
    interests    = { S = "beaches, snorkeling, hiking" }
    VacationCost = { N = "3100" }
    TravelPlan   = { S = "5-day tropical escape: Day 1 Waikiki beach relaxation; Day 2 Diamond Head crater hike and North Shore shrimp trucks; Day 3 Hanauma Bay snorkeling and coastal trails; Day 4 Pearl Harbor historic tour and evening luau; Day 5 Beach relaxation and departure." }
  })
}

resource "aws_dynamodb_table_item" "item_3" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity         = { S = "Tokyo" }
    Duration     = { N = "10" }
    origin       = { S = "San Francisco" }
    travel_dates = { S = "October 8-18, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$6,500" }
    interests    = { S = "food, technology, temples" }
    VacationCost = { N = "5900" }
    TravelPlan   = { S = "10-day Tokyo discovery: Day 1-3 Shibuya, Shinjuku, Tsukiji market food tour; Day 4-5 Asakusa Senso-ji and Akihabara; Day 6 Day trip to Mt. Fuji and Hakone onsen; Day 7-8 Harajuku, Meiji Jingu, TeamLab digital art; Day 9 Ginza culinary and ramen tour; Day 10 Departure." }
  })
}

resource "aws_dynamodb_table_item" "item_4" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity         = { S = "Banff" }
    Duration     = { N = "6" }
    origin       = { S = "Seattle" }
    travel_dates = { S = "July 5-11, 2027" }
    travelers    = { S = "2 adults, 1 child" }
    budget       = { S = "$4,200" }
    interests    = { S = "nature, hiking, wildlife" }
    VacationCost = { N = "3800" }
    TravelPlan   = { S = "6-day Canadian Rockies adventure: Day 1 Banff town and gondola; Day 2 Lake Louise and Lake Agnes teahouse hike; Day 3 Moraine Lake canoeing and Sentinel Pass; Day 4 Icefields Parkway glacier tour; Day 5 Johnston Canyon falls hike; Day 6 Upper Hot Springs and departure." }
  })
}

resource "aws_dynamodb_table_item" "item_5" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity   = { S = "Sedona" }
    Duration     = { N = "4" }
    origin       = { S = "Los Angeles" }
    travel_dates = { S = "September 18-22, 2027" }
    travelers    = { S = "4 adults" }
    budget       = { S = "$2,800" }
    interests    = { S = "hiking, stargazing, wellness" }
    VacationCost = { N = "2400" }
    TravelPlan   = { S = "4-day red rock wellness retreat: Day 1 Bell Rock trail & sunset vortex; Day 2 Cathedral Rock sunrise hike and Pink Jeep tour; Day 3 Oak Creek Canyon and Tlaquepaque arts village; Day 4 Stargazing night session and departure." }
  })
}