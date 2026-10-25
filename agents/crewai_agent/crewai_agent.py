from crewai import Agent, Task, Crew, Process
from crewai import LLM

mistral_llm = LLM(
    model="mistral/mistral-large-latest",
    temperature=0.7,
)

agent = Agent(
    role="Senior Research Analyst",
    goal="Find and summarize the latest trends in AI agents",
    backstory=(
        "You are a veteran analyst known for sharp, concise insight "
        "into emerging technology trends."
    ),
    llm=mistral_llm,
    verbose=True,
)

task = Task(
    description=(
        "Research the latest developments in AI agents and summarize "
        "the 3 most important trends in a short bullet list."
    ),
    expected_output="A markdown bullet list with 3 trends and a one-line explanation for each.",
    agent=agent,
)

crew = Crew(
    agents=[agent],
    tasks=[task],
    process=Process.sequential,
    verbose=True,
)

if __name__ == "__main__":
    result = crew.kickoff()
    print("\n=== Final Output ===")
    print(result)