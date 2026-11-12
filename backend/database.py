import os
import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from contextlib import contextmanager

DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")
DB_NAME = os.getenv("DB_NAME", "ragdb")
INSTANCE_CONNECTION_NAME = os.getenv(
    "INSTANCE_CONNECTION_NAME"
)  # format: project:region:instance
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")  # fallback for local testing
DB_PORT = os.getenv("DB_PORT", "5432")

# Determine whether to use Unix socket (Cloud Run) or TCP (local)
if INSTANCE_CONNECTION_NAME:
    db_config = {
        "dbname": DB_NAME,
        "user": DB_USER,
        "password": DB_PASS,
        "host": f"/cloudsql/{INSTANCE_CONNECTION_NAME}",
    }
else:
    db_config = {
        "dbname": DB_NAME,
        "user": DB_USER,
        "password": DB_PASS,
        "host": DB_HOST,
        "port": DB_PORT,
    }

pool = ThreadedConnectionPool(minconn=1, maxconn=10, **db_config)


@contextmanager
def get_db_connection():
    conn = pool.getconn()
    try:
        yield conn
    finally:
        pool.putconn(conn)


def init_db():
    """Initializes the database schema with pgvector."""
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS documents (
                    id SERIAL PRIMARY KEY,
                    file_path TEXT UNIQUE NOT NULL,
                    document_name TEXT NOT NULL,
                    content BYTEA NOT NULL
                );
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS document_chunks (
                    id SERIAL PRIMARY KEY,
                    document_name TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    header_path TEXT,
                    content TEXT NOT NULL,
                    metadata JSONB DEFAULT '{}'::jsonb,
                    embedding VECTOR(3072),
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                );
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_chunks_file_path 
                ON document_chunks (file_path);
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_chunks_embedding_halfvec
                ON document_chunks 
                USING hnsw ((embedding::halfvec(3072)) halfvec_cosine_ops)
                WITH (m = 16, ef_construction = 64);
            """)
        conn.commit()
