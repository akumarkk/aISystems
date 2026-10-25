import os
from crewai import LLM
from dotenv import load_dotenv

load_dotenv()

# Initialize the Bedrock Claude LLM
llm = LLM(
    model="bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0",
    region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
)

try:
  print("Sending test prompt to Claude via AWS Bedrock...")
  # Call the LLM directly with a simple prompt string or message structure
  response = llm.call(
      [{"role": "user", "content": "Say 'Connection successful!' and nothing else."}]
  )
  print("\nResponse received:")
  print(response)
  print("\nSUCCESS: Bedrock Claude integration is working correctly!")
except Exception as e:
  print(f"\nFAILURE: Connection failed with error:\n{e}")