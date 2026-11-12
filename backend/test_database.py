import unittest
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import quote
from uuid import uuid4

from fastapi.testclient import TestClient

from database import get_db_connection, init_db
from main import app, QueryRequest, query_rag


class DatabaseIntegrationTests(unittest.IsolatedAsyncioTestCase):
    """Run against a disposable PostgreSQL database with pgvector."""

    def setUp(self):
        init_db()
        self.file_path = f"test/{uuid4()}"
        self.addCleanup(self.delete_chunks)

    def delete_chunks(self):
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "DELETE FROM document_chunks WHERE file_path = %s;",
                    (self.file_path,),
                )
            conn.commit()

    def test_startup_is_idempotent(self):
        init_db()

    async def test_query_retrieves_3072_dimensional_embedding(self):
        embedding = [1.0] + [0.0] * 3071
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO document_chunks
                        (document_name, file_path, content, embedding)
                    VALUES (%s, %s, %s, %s);
                    """,
                    ("test.txt", self.file_path, "A test document.", embedding),
                )
            conn.commit()

        with patch("main.client") as client, patch("main.ranker") as ranker:
            client.models.embed_content.return_value = SimpleNamespace(
                embeddings=[SimpleNamespace(values=embedding)]
            )
            client.models.generate_content.return_value = SimpleNamespace(
                text="A test answer."
            )
            ranker.rerank.side_effect = lambda request: [
                {**passage, "score": 1.0} for passage in request.passages
            ]

            response = await query_rag(QueryRequest(query="A test question?"))

        self.assertEqual(response.answer, "A test answer.")
        self.assertEqual(response.citations[0].file_path, self.file_path)
        self.assertIsNone(response.citations[0].download_url)


class DocumentDownloadIntegrationTests(unittest.TestCase):
    def setUp(self):
        init_db()
        self.filename = f"r\u00e9sum\u00e9 #{uuid4()}.pdf"
        self.file_path = f"uploads/{self.filename}"
        self.addCleanup(self.delete_document)
        self.http = self.enterContext(TestClient(app, raise_server_exceptions=False))
        self.client = self.enterContext(patch("main.client"))
        self.converter = self.enterContext(patch("main.md"))
        self.ranker = self.enterContext(patch("main.ranker"))
        self.embedding = [1.0] + [0.0] * 3071
        self.client.models.embed_content.return_value = SimpleNamespace(
            embeddings=[SimpleNamespace(values=self.embedding)]
        )
        self.client.models.generate_content.return_value = SimpleNamespace(
            text="A test answer."
        )
        self.converter.convert.return_value = SimpleNamespace(
            text_content="# Test\n\nA test document."
        )
        self.ranker.rerank.side_effect = lambda request: [
            {**passage, "score": 1.0} for passage in request.passages
        ]

    def delete_document(self):
        with get_db_connection() as conn, conn:
            with conn.cursor() as cur:
                cur.execute(
                    "DELETE FROM document_chunks WHERE file_path = %s;",
                    (self.file_path,),
                )
                cur.execute(
                    "DELETE FROM documents WHERE file_path = %s;",
                    (self.file_path,),
                )

    def upload(self, content):
        return self.http.post(
            "/ingest",
            files={"file": (self.filename, content, "application/pdf")},
        )

    def test_answer_download_preserves_original_bytes_and_filename(self):
        original = b"%PDF-1.7\r\n\x00\xffOriginal document bytes."
        self.assertEqual(self.upload(original).status_code, 200)

        answer = self.http.post("/query", json={"query": "A test question?"})
        self.assertEqual(answer.status_code, 200)
        citation = answer.json()["citations"][0]
        self.assertEqual(citation["document_name"], self.filename)
        self.assertEqual(citation["file_path"], self.file_path)

        download = self.http.get(citation["download_url"])
        self.assertEqual(download.status_code, 200)
        self.assertEqual(download.content, original)
        self.assertEqual(download.headers["content-type"], "application/octet-stream")
        self.assertEqual(
            download.headers["content-disposition"],
            f"attachment; filename*=UTF-8''{quote(self.filename, safe='')}",
        )

    def test_reupload_replaces_original_and_rolls_back_failed_indexing(self):
        original = b"Original bytes."
        self.assertEqual(self.upload(original).status_code, 200)
        answer = self.http.post("/query", json={"query": "A test question?"})
        download_url = answer.json()["citations"][0]["download_url"]

        self.client.models.embed_content.return_value = SimpleNamespace(
            embeddings=[SimpleNamespace(values=[1.0, 0.0])]
        )
        self.assertEqual(self.upload(b"Failed replacement.").status_code, 500)
        self.assertEqual(self.http.get(download_url).content, original)

        self.client.models.embed_content.return_value = SimpleNamespace(
            embeddings=[SimpleNamespace(values=self.embedding)]
        )
        self.converter.convert.return_value = SimpleNamespace(
            text_content="# Replacement\n\nUpdated document."
        )
        replacement = b"Replacement bytes."
        self.assertEqual(self.upload(replacement).status_code, 200)
        init_db()
        self.assertEqual(self.http.get(download_url).content, replacement)
        answer = self.http.post("/query", json={"query": "A test question?"})
        citations = answer.json()["citations"]
        self.assertEqual(len(citations), 1)
        self.assertEqual(citations[0]["download_url"], download_url)
        self.assertIn("Updated document.", citations[0]["content"])

    def test_unknown_document_returns_404(self):
        response = self.http.get("/documents/-1/download")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["detail"], "Original document not found.")


if __name__ == "__main__":
    unittest.main()
