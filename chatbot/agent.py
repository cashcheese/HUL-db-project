"""
agent.py
--------
LangChain agent setup with Gemini, SQLDatabase, stored procedure tools, and memory.
"""

import os
import sys
from dotenv import load_dotenv
from urllib.parse import quote_plus

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

#from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_groq import ChatGroq
from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits import SQLDatabaseToolkit
from langchain.agents import AgentExecutor
from langchain.agents.react.agent import create_react_agent
from langchain.memory import ConversationBufferWindowMemory
from langchain_core.prompts import PromptTemplate

from chatbot.tools import ALL_TOOLS


# ── LLM ───────────────────────────────────────────────────────────────────────

def get_llm():
    return ChatGroq(
        model="llama-3.3-70b-versatile",
        groq_api_key=os.getenv("GROQ_API_KEY"),
        temperature=0.1,
    )


# ── Database (READ ONLY) ───────────────────────────────────────────────────────

READ_ONLY_TABLES = [
    'Product', 'FinishedGood', 'RawMaterial', 'Brand',
    'Supplier', 'Supplies', 'BillOfItems',
    'Inventory', 'Batch', 'Warehouse',
    'DistributionOrder', 'DistributionOrderLine',
    'Customer', 'Channel', 'Customer_Channel',
    'PurchaseOrder', 'POLineItem',
    'Shipment', 'ShipmentDetails',
    'Invoice', 'Payment',
    'ManufacturingOrder', 'Factory', 'GoodsReceipt',
]

# Cache the DB connection — expensive to rebuild every request
_db_cache = None

def get_database():
    global _db_cache
    if _db_cache is None:
        host     = os.getenv("DB_HOST", "localhost")
        user     = os.getenv("DB_USER")
        password = quote_plus(os.getenv("DB_PASSWORD"))
        db_name  = os.getenv("DB_NAME", "hul_db")
        uri      = f"mysql+mysqlconnector://{user}:{password}@{host}/{db_name}"
        _db_cache = SQLDatabase.from_uri(
            uri,
            #include_tables=READ_ONLY_TABLES,
            sample_rows_in_table_info=2
        )
    return _db_cache


# ── System Prompt ──────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are a supply chain assistant for HUL (Hindustan Unilever Limited).
You help warehouse managers and admins query supply chain data and take actions.

You have access to these tools:
{tools}

RULES:
1. For data questions use SQL tools to query the database directly.
2. For common operations (pending orders, inventory, forecasts) use the dedicated procedure tools — they are faster and more reliable than raw SQL.
3. For write operations (allocating orders, recording payments) ONLY use the dedicated write tools. NEVER generate INSERT, UPDATE, or DELETE SQL yourself.
4. Always confirm with the user before performing any write operation.
5. Keep answers concise and focused on supply chain operations.
6. If you cannot answer something, say so clearly.

Product IDs:
- 2001 = Bru Instant Coffee 50g Jar
- 2002 = Knorr Classic Thick Tomato Soup 50g
- 2003 = Surf Excel Matic Top Load 1kg

Customer IDs:
- 501 = DMart Whitefield
- 502 = Sharma General Store
- 503 = Taj MG Road

Format:
Question: the input question
Thought: think about what to do
Action: one of [{tool_names}]
Action Input: input to the action
Observation: result of the action
... (repeat Thought/Action/Action Input/Observation as needed)
Thought: I now know the final answer
Final Answer: the final answer

Begin!

Previous conversation:
{chat_history}

Question: {input}
Thought: {agent_scratchpad}"""


# ── Memory store (per session) ─────────────────────────────────────────────────

_memory_store = {}

def get_memory(session_id: str) -> ConversationBufferWindowMemory:
    if session_id not in _memory_store:
        _memory_store[session_id] = ConversationBufferWindowMemory(
            k=6,
            memory_key="chat_history",
            return_messages=False,
            input_key="input"
        )
    return _memory_store[session_id]


def clear_memory(session_id: str):
    if session_id in _memory_store:
        del _memory_store[session_id]


# ── Agent builder ──────────────────────────────────────────────────────────────

def build_agent_executor(session_id: str) -> AgentExecutor:
    llm = get_llm()
    db  = get_database()

    sql_toolkit = SQLDatabaseToolkit(db=db, llm=llm)
    sql_tools   = sql_toolkit.get_tools()

    all_tools = sql_tools + ALL_TOOLS

    prompt = PromptTemplate.from_template(SYSTEM_PROMPT)

    agent = create_react_agent(
        llm=llm,
        tools=all_tools,
        prompt=prompt
    )

    executor = AgentExecutor(
        agent=agent,
        tools=all_tools,
        memory=get_memory(session_id),
        verbose=True,
        max_iterations=8,
        handle_parsing_errors=True,
        return_intermediate_steps=False
    )

    return executor


# ── Main chat function ─────────────────────────────────────────────────────────

def chat(user_message: str, session_id: str) -> str:
    try:
        executor = build_agent_executor(session_id)
        result   = executor.invoke({"input": user_message})
        return result.get("output", "I could not generate a response.")
    except Exception as e:
        error_msg = str(e)
        if "quota" in error_msg.lower():
            return "API quota exceeded. Please try again in a moment."
        if "invalid" in error_msg.lower() and "key" in error_msg.lower():
            return "Invalid API key. Please check your GEMINI_API_KEY in .env."
        return f"Error: {error_msg}"