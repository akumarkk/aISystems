##### Wiki: Memory Event Lifecycle & Context Passing Architecture
**Stack:** CrewAI (Orchestration) | AWS Lambda (Execution) | AgentCore Gateway (Runtime & AgentCore Memory)

---

## 1. Interaction Lifecycle Matrix

| Phase | Step / Action | Component Responsible | Key Operations & Data Flow |
| :--- | :--- | :--- | :--- |
| **1. Pre-Execution** | Inbound Request Logging | AgentCore Gateway / Lambda Entry Point | • Receive payload (`ActorId`, `SessionId`, user prompt)<br>• Call `create_event` (`role='USER'`) |
| **2. Context Retrieval** | Fetch Short/Long-Term Memory | Lambda (Pre-Crew Initialization) | • Retrieve recent chat history & extracted user facts<br>• Combine into CrewAI `inputs` or Agent backstories |
| **3. CrewAI Execution** | Multi-Agent Orchestration | CrewAI Engine inside Lambda | • Agents execute tasks and run custom tools<br>• *(Optional)* Call `create_event` (`role='TOOL'`) for key state changes |
| **4. Post-Execution** | Outbound Event Logging & Response | Lambda Exit Point / AgentCore Gateway | • Call `create_event` (`role='ASSISTANT'`) with final CrewAI result<br>• Return HTTP response to caller |

---

## 2. Event & Context Management Strategy

### A. Pre-Execution Phase (Inbound Request)
1. **Log User Event (`create_event` with `role='USER'`):**  
   * **When:** Immediately upon receiving the Lambda payload, before running any CrewAI logic.
   * **Why:** Guarantees immediate persistence of the prompt in short-term context even if the execution fails or times out downstream.

2. **Fetch Memory Context (`get_memory_context` / long-term memory query):**  
   * **When:** Right after logging the user event and prior to CrewAI setup.
   * **How to Pass:** Inject retrieved short-term chat history and long-term user preferences into CrewAI via the `inputs` dictionary or directly inside Agent `backstory` templates.

---

### B. Execution Phase (Crew Orchestration)
1. **Log Tool Events (`create_event` with `role='TOOL'`):**  
   * **When:** Inside custom CrewAI tools when executing critical external side effects (e.g., database writes, third-party API mutations).
   * **Best Practice:** Pass `extractionMode='SKIP'` so intermediate raw tool outputs persist in short-term execution logs without polluting long-term memory profiles.

---

### C. Post-Execution Phase (Outbound Response)
1. **Log Assistant Event (`create_event` with `role='ASSISTANT'`):**  
   * **When:** Immediately after `crew.kickoff()` completes and produces the final aggregate response.
   * **Why:** Completes the conversation turn in short-term memory and triggers background processors for long-term entity/preference extraction.

---

## 3. Reference Implementation (Python / Boto3)

```python
import os
import boto3
from crewai import Agent, Crew, Process, Task

agentcore_client = boto3.client('bedrock-agentcore')

def lambda_handler(event, context):
    memory_id = os.environ['MEMORY_ID']
    actor_id = event.get('actorId', 'user-default')
    session_id = event.get('sessionId', 'session-default')
    user_prompt = event.get('prompt', '')

    # -------------------------------------------------------------
    # 1. CREATE EVENT: Log Inbound User Request
    # -------------------------------------------------------------
    agentcore_client.create_event(
        memoryId=memory_id,
        actorId=actor_id,
        sessionId=session_id,
        payload=[{
            'conversational': {
                'role': 'USER',
                'content': {'text': user_prompt}
            }
        }]
    )

    # -------------------------------------------------------------
    # 2. FETCH CONTEXT: Retrieve Past Interactions & Preferences
    # -------------------------------------------------------------
    memory_context = agentcore_client.get_memory_context(
        memoryId=memory_id,
        actorId=actor_id,
        sessionId=session_id
    )
    retrieved_facts = memory_context.get('contextText', '')

    # -------------------------------------------------------------
    # 3. RUN CREWAI: Inject Context into Crew Execution
    # -------------------------------------------------------------
    researcher = Agent(
        role='Context-Aware Researcher',
        goal='Analyze requests while considering historical user preferences',
        backstory=f'You are an AI assistant. Relevant User Context: {retrieved_facts}'
    )

    task = Task(
        description=f'Address the following prompt: {user_prompt}',
        expected_output='A thorough, personalized response.',
        agent=researcher
    )

    crew = Crew(
        agents=[researcher],
        tasks=[task],
        process=Process.sequential
    )

    crew_result = str(crew.kickoff())

    # -------------------------------------------------------------
    # 4. CREATE EVENT: Log Outbound Assistant Response
    # -------------------------------------------------------------
    agentcore_client.create_event(
        memoryId=memory_id,
        actorId=actor_id,
        sessionId=session_id,
        payload=[{
            'conversational': {
                'role': 'ASSISTANT',
                'content': {'text': crew_result}
            }
        }]
    )

    return {
        'statusCode': 200,
        'body': {
            'response': crew_result,
            'sessionId': session_id,
            'actorId': actor_id
        }
    }
    ```