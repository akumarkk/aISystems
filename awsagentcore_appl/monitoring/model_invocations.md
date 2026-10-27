##### model invocations

If nothing appears under Model Invocations, it usually means your agent is either directly hitting an external API endpoint for its LLM (like calling Mistral's API directly using the secret we saw earlier) rather than routing inference through an AWS Bedrock managed model, or Bedrock model invocation logging hasn't been enabled in your account console.