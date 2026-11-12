# rag+gcp
Rag on  GCP

## Run locally with Docker Compose

Requires Docker with the Compose plugin and a Gemini API key.

```sh
export GEMINI_API_KEY="your-gemini-api-key"
docker compose up --build -d
```

- Frontend: http://localhost:3000
- Backend API: http://localhost:8080 (docs at `/docs`, health at `/health`)
- PostgreSQL with pgvector runs on the internal Compose network. Data persists
  in the `postgres_data` volume, and the backend initializes the schema on startup.
  Embeddings are stored as 3,072-dimensional vectors. Retrieval uses a
  half-precision HNSW expression index (requires pgvector 0.7.0 or newer),
  since regular vector HNSW indexes support at most 2,000 dimensions.

The frontend image builds with `http://localhost:8080` as its browser-facing API
URL. The backend waits for PostgreSQL, and the frontend waits for the backend
health check. The first build downloads dependencies and the FlashRank model.
Document ingestion and queries use Gemini and require internet access.
The database credentials in Compose are for local development only.

### Download original documents

New uploads retain their original bytes in PostgreSQL, in the same transaction
as their indexed chunks. Each answer citation includes a **Download original
document** link, served by `GET /documents/{document_id}/download`.
Re-uploading the same filename replaces both the original and its indexed chunks.
Originals persist with the database, including across container restarts.

Documents indexed before this feature must be re-uploaded to enable downloads.
As with ingestion and querying, downloads currently have no authentication; keep
the app restricted to trusted users.

```sh
docker compose logs -f
docker compose down
```

Stopping the stack preserves database data. To also delete the local database:

```sh
docker compose down -v
```

## Backend formatting

The backend has its own Prettier configuration for supported files such as JSON,
YAML, and Markdown. Python files are explicitly excluded; Prettier does not
format Python. These commands require Node.js and npm:

```sh
cd backend
npx prettier@3 --write . --ignore-unknown
npx prettier@3 --check . --ignore-unknown
```

In VS Code, the Prettier extension discovers the backend configuration
automatically. Do not select Prettier as the formatter for Python files.
