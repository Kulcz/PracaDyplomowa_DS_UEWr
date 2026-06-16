from langchain import hub
from langchain.agents import AgentExecutor, create_openai_functions_agent
from langchain_openai import ChatOpenAI

instructions = """You are an expert researcher."""
base_prompt = hub.pull("langchain-ai/openai-functions-template")
prompt = base_prompt.partial(instructions=instructions)

llm = ChatOpenAI(openai_api_key="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", temperature=0)

from langchain_community.tools.semanticscholar.tool import SemanticScholarQueryRun
tools = [SemanticScholarQueryRun()]
agent = create_openai_functions_agent(llm, tools, prompt)

agent_executor = AgentExecutor(
    agent=agent,
    tools=tools,
    verbose=True,
)

agent_executor.invoke(
    {
        "input": "How elemental sulphur fertilisation affects crop yields? "
        "show me a list of papers and techniques. Based on your findings write new research questions "
        "to work on. Break down the task into subtasks for search. Use the search tool"}
)
