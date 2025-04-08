from langchain_core.globals import set_verbose, set_debug
from langchain_ollama import OllamaEmbeddings
from langchain_openai import ChatOpenAI
from langchain.schema.output_parser import StrOutputParser
from langchain_community.vectorstores import Chroma
from langchain_community.document_loaders import TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.schema.runnable import RunnablePassthrough
from langchain_community.vectorstores.utils import filter_complex_metadata
from langchain_core.prompts import ChatPromptTemplate
import logging
import pathlib
import os

if "OPENAI_API_KEY" not in os.environ:
    os.environ["OPENAI_API_KEY"] = ""

set_debug(True)
set_verbose(True)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class loader:

    def __init__(self, llm_model: str = "gpt-4o", embedding_model: str = "mxbai-embed-large"):
        self.model = ChatOpenAI(model=llm_model)
        self.embeddings = OllamaEmbeddings(model=embedding_model)
        self.text_splitter = RecursiveCharacterTextSplitter(chunk_size=1024, chunk_overlap=100)
        self.prompt = ChatPromptTemplate.from_template(
            """
            You are a legal advisor focused on transit laws in Bolivia. You will be given snippets of the Bolivian law in Spanish. You must answer back in Spanish only referencing the snippets you were given as context and citing them if possible.
            Context:
            {context}
            
            Question:
            {question}
            
            Responde de manera concisa y acertada en 3 oraciones como maximo.
            """
        )
        self.vector_store = None
        self.retriever = None
        
        if (not os.path.isfile("chroma_db/chroma.sqlite3")):
            self.ingest("codigos.txt")
        else:
            self.vector_store = Chroma(embedding_function=self.embeddings, persist_directory="chroma_db")

    def ingest(self, file_path: str):
        file_path = pathlib.Path(__file__).parent / file_path
        print(file_path)
        logger.info(f"Starting ingestion for file: {file_path}")
        docs = TextLoader(file_path=file_path, encoding="UTF-8").load()
        chunks = self.text_splitter.split_documents(docs)
        chunks = filter_complex_metadata(chunks)

        self.vector_store = Chroma.from_documents(
            documents=chunks,
            embedding=self.embeddings,
            persist_directory="chroma_db",
        )
        logger.info("Ingestion completed. Document embeddings stored successfully.")

    def ask(self, query: str, k: int = 5, score_threshold: float = 0.2):
        if not self.vector_store:
            raise ValueError("No vector store found. Please ingest a document first.")

        if not self.retriever:
            self.retriever = self.vector_store.as_retriever(
                search_type="similarity_score_threshold",
                search_kwargs={"k": k, "score_threshold": score_threshold},
            )

        logger.info(f"Retrieving context for query: {query}")
        retrieved_docs = self.retriever.invoke(query)

        if not retrieved_docs:
            return "No relevant context found in the document to answer your question."

        formatted_input = {
            "context": "\n\n".join(doc.page_content for doc in retrieved_docs),
            "question": query,
        }


        chain = (
            RunnablePassthrough() 
            | self.prompt         
            | self.model      
            | StrOutputParser()  
        )

        logger.info("Generating response using the LLM.")
        return chain.invoke(formatted_input)

    def clear(self):
        """
        Reset the vector store and retriever.
        """
        logger.info("Clearing vector store and retriever.")
        self.vector_store = None
        self.retriever = None
