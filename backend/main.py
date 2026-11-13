import os
import json
import shutil
import tempfile
from pathlib import Path
from typing import List, Literal, Optional
from urllib.parse import quote

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from markitdown import MarkItDown
from flashrank import Ranker, RerankRequest
from langchain_text_splitters import MarkdownHeaderTextSplitter

from database import init_db, get_db_connection

app = FastAPI(title="Gemini Cloud Run RAG")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For production, replace "*" with your frontend Cloud Run URL
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize models and utilities
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
ranker = Ranker(model_name="ms-marco-MiniLM-L-12-v2")
md = MarkItDown()

markdown_splitter = MarkdownHeaderTextSplitter(
    headers_to_split_on=[("#", "H1"), ("##", "H2"), ("###", "H3")]
)


@app.on_event("startup")
def on_startup():
    init_db()


# Request/Response schemas
class QueryRequest(BaseModel):
    query: str
    language: Literal["en", "es"] = "en"
    top_candidates: int = 25
    top_reranked: int = 5


class Citation(BaseModel):
    file_path: str
    document_name: str
    content: str
    score: float
    download_url: Optional[str] = None


class QueryResponse(BaseModel):
    answer: str
    citations: List[Citation]


@app.post("/ingest")
async def ingest_document(file: UploadFile = File(...)):
    """Uploads, parses via MarkItDown, chunks, embeds, and stores in Cloud SQL."""
    suffix = Path(file.filename).suffix
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
        shutil.copyfileobj(file.file, tmp_file)
        tmp_path = tmp_file.name

    try:
        # 1. Convert to Markdown using MarkItDown
        converted = md.convert(tmp_path)
        markdown_text = converted.text_content

        if not markdown_text.strip():
            raise HTTPException(
                status_code=400, detail="Could not extract text from file."
            )

        # 2. Split into markdown-aware chunks
        chunks = markdown_splitter.split_text(markdown_text)
        if not chunks:
            # Fallback for documents without markdown headers
            from langchain_text_splitters import RecursiveCharacterTextSplitter

            fallback_splitter = RecursiveCharacterTextSplitter(
                chunk_size=1000, chunk_overlap=150
            )
            chunks = fallback_splitter.create_documents([markdown_text])

        chunk_texts = [c.page_content for c in chunks]

        # 3. Embed with Gemini text-embedding-004 (in batches of 50)
        batch_size = 50
        all_embeddings = []
        for i in range(0, len(chunk_texts), batch_size):
            batch = chunk_texts[i : i + batch_size]
            res = client.models.embed_content(
                model="gemini-embedding-001",
                contents=batch,
            )
            all_embeddings.extend([item.values for item in res.embeddings])

        # 4. Insert into Cloud SQL
        storage_path = f"uploads/{file.filename}"  # Or your Cloud Storage gs:// URI
        with get_db_connection() as conn, conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO documents (file_path, document_name, content)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (file_path) DO UPDATE
                    SET document_name = EXCLUDED.document_name,
                        content = EXCLUDED.content;
                """,
                    (storage_path, file.filename, Path(tmp_path).read_bytes()),
                )

                # Remove prior entries if replacing
                cur.execute(
                    "DELETE FROM document_chunks WHERE file_path = %s;", (storage_path,)
                )

                for chunk, emb in zip(chunks, all_embeddings):
                    meta = chunk.metadata if hasattr(chunk, "metadata") else {}
                    header_path = (
                        " > ".join([f"{k}: {v}" for k, v in meta.items()])
                        if meta
                        else None
                    )

                    cur.execute(
                        """
                        INSERT INTO document_chunks 
                        (document_name, file_path, header_path, content, metadata, embedding)
                        VALUES (%s, %s, %s, %s, %s, %s);
                    """,
                        (
                            file.filename,
                            storage_path,
                            header_path,
                            chunk.page_content,
                            json.dumps(meta),
                            emb,
                        ),
                    )

        return {
            "status": "success",
            "document_name": file.filename,
            "chunks_indexed": len(chunks),
        }

    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.get("/documents/{document_id}/download")
def download_document(document_id: int):
    with get_db_connection() as conn, conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT document_name, content FROM documents WHERE id = %s;",
                (document_id,),
            )
            document = cur.fetchone()

    if document is None:
        raise HTTPException(status_code=404, detail="Original document not found.")

    document_name, content = document
    return Response(
        content=bytes(content),
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(document_name, safe='')}"
        },
    )


@app.post("/query", response_model=QueryResponse)
async def query_rag(req: QueryRequest):
    """Embeds query, fetches top candidates from Cloud SQL, reranks, and calls Gemini."""

    # 1. Embed query
    query_emb_res = client.models.embed_content(
        model="gemini-embedding-001", contents=req.query
    )
    query_vector = query_emb_res.embeddings[0].values

    # 2. Stage 1: Dense Retrieval in Cloud SQL (pgvector)
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            # Tune HNSW search quality
            cur.execute("SET hnsw.ef_search = 100;")
            cur.execute(
                """
                SELECT c.id, c.document_name, c.file_path, c.content,
                    (c.embedding::halfvec(3072) <=> %s::halfvec(3072)) AS distance,
                    d.id
                FROM document_chunks c
                LEFT JOIN documents d ON d.file_path = c.file_path
                ORDER BY distance ASC
                LIMIT %s;
            """,
                (query_vector, req.top_candidates),
            )
            rows = cur.fetchall()

    if not rows:
        answer = (
            "No se encontraron documentos en la base de datos."
            if req.language == "es"
            else "No documents found in database."
        )
        return QueryResponse(answer=answer, citations=[])

    # 3. Stage 2: Rerank using FlashRank
    passages = [
        {
            "id": r[0],
            "text": r[3],
            "doc_name": r[1],
            "file_path": r[2],
            "download_url": f"/documents/{r[5]}/download" if r[5] is not None else None,
        }
        for r in rows
    ]
    rerank_req = RerankRequest(query=req.query, passages=passages)
    reranked = ranker.rerank(rerank_req)
    top_ranked = reranked[: req.top_reranked]

    # Format context for Gemini
    context_blocks = []
    citations = []
    for item in top_ranked:
        citations.append(
            Citation(
                document_name=item["doc_name"],
                file_path=item["file_path"],
                content=item["text"],
                score=float(item["score"]),
                download_url=item["download_url"],
            )
        )
        context_blocks.append(f"[File: {item['file_path']}]\n{item['text']}")

    full_context = "\n\n---\n\n".join(context_blocks)

    # 4. Generate Answer with Gemini
    response_language = "Spanish" if req.language == "es" else "English"
    prompt = f"""You are a helpful and precise assistant. 
Answer the following question solely based on the provided Markdown context. 
Respond in {response_language}, even if the question or context uses another language.
If the information is not in the context, explicitly state that you don't know. 
Always reference the file path when citing facts.
Keep document names and file paths unchanged.

Context:
{full_context}

User Question:
{req.query}
"""

    llm_response = client.models.generate_content(
        model="gemini-3.1-flash-lite", contents=prompt
    )

    return QueryResponse(answer=llm_response.text, citations=citations)


@app.get("/health")
def health():
    return {"status": "ok"}
