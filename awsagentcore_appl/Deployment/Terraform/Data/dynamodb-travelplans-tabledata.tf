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

resource "aws_dynamodb_table_item" "item_6" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity   = { S = "Lisbon" }
    Duration     = { N = "5" }
    origin       = { S = "Boston" }
    travel_dates = { S = "May 14-19, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$3,800" }
    interests    = { S = "history, food, coastal views" }
    VacationCost = { N = "3400" }
    TravelPlan   = { S = "5-day Lisbon highlights: Day 1 Alfama district walk & Fado show; Day 2 Belém Tower and Jerónimos Monastery; Day 3 Day trip to Sintra palaces; Day 4 Cascais coastal exploration; Day 5 Time Out Market culinary tour & departure." }
  })
}

resource "aws_dynamodb_table_item" "item_7" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity   = { S = "San Sebastian" }
    Duration     = { N = "4" }
    origin       = { S = "Chicago" }
    travel_dates = { S = "June 20-24, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$3,200" }
    interests    = { S = "pintxos, beaches, culinary arts" }
    VacationCost = { N = "2900" }
    TravelPlan   = { S = "4-day Basque culinary journey: Day 1 La Concha Beach & Parte Vieja pintxos tour; Day 2 Mount Igueldo funicular & Miramar Palace; Day 3 Michelin-starred dining & Zurriola surf beach; Day 4 Peine del Viento coastal stroll & departure." }
  })
}

resource "aws_dynamodb_table_item" "item_8" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity   = { S = "Porto" }
    Duration     = { N = "4" }
    origin       = { S = "Miami" }
    travel_dates = { S = "October 4-8, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$3,000" }
    interests    = { S = "wine tasting, architecture, river cruises" }
    VacationCost = { N = "2600" }
    TravelPlan   = { S = "4-day Porto wine & river experience: Day 1 Ribeira district & Dom Luís I Bridge; Day 2 Vila Nova de Gaia port wine cellars; Day 3 Douro Valley river cruise & vineyard lunch; Day 4 Livraria Lello & São Bento Station stroll before departure." }
  })
}

resource "aws_dynamodb_table_item" "item_9" {
  table_name = data.aws_dynamodb_table.travel_plans.name
  hash_key   = data.aws_dynamodb_table.travel_plans.hash_key
  range_key  = data.aws_dynamodb_table.travel_plans.range_key

  item = jsonencode({
    TravelCity   = { S = "Rome" }
    Duration     = { N = "6" }
    origin       = { S = "Washington DC" }
    travel_dates = { S = "April 18-24, 2027" }
    travelers    = { S = "2 adults" }
    budget       = { S = "$4,500" }
    interests    = { S = "history, ancient art, cuisine" }
    VacationCost = { N = "3900" }
    TravelPlan   = { S = "6-day Eternal City immersion: Day 1 Colosseum & Roman Forum; Day 2 Vatican City, St. Peter's & Sistine Chapel; Day 3 Trevi Fountain, Pantheon & Piazza Navona; Day 4 Trastevere food walk & Villa Borghese gardens; Day 5 Day trip to Tivoli (Villa d'Este); Day 6 Spanish Steps & departure." }
  })
}
