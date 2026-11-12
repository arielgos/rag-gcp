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

## Frontend development

The frontend uses React, TypeScript, and Vite. With Node.js 20.19+ and npm:

```sh
cd frontend
npm ci
npm run dev
```

The development server runs at http://localhost:3000 and connects to the backend
at http://localhost:8080 by default. Set `VITE_API_URL` to use another backend.
This variable is embedded at build time for production.

```sh
npm run typecheck
npm run build
```

The production build type-checks both the React application and Vite configuration
before bundling. Docker uses the same build command.

The app layout lives in `frontend/src/App.tsx`. Feature components are in
`frontend/src/components/`: `DocumentIngestion` handles uploads, `QueryPanel`
handles questions, and `AnswerCard` and `CitationCard` display answers and sources.
Shared API requests and response types live in `frontend/src/api.ts`.

### Frontend languages

The UI supports English and Spanish using i18next and react-i18next. It first
checks the saved language preference, then the browser's preferred languages,
and falls back to English. Regional variants such as `es-AR` use their base
language. The header language selector saves the choice in local storage under
`rag-language`. The page's language metadata is updated with the selection.

Translations live in `frontend/src/locales/en.json` and `es.json`; keep their
keys aligned. Translation keys are type-checked against the English dictionary.
To add another language, add its dictionary and register it in
`frontend/src/i18n.ts` and `LanguageSwitcher`. Also extend the query-language
mapping in `frontend/src/api.ts` and the backend's `QueryRequest` schema and
answer-language instructions.

Queries send the active UI language as `language: "en"` or `language: "es"` to
`POST /query`. The backend requests a generated answer in that language, regardless
of the question or document language. Its empty-database response is also
localized. Clients that omit `language` default to English; unsupported language
codes return HTTP 422. Changing the UI language affects subsequent queries, not
answers already displayed.

Uploaded documents, filenames, retrieved source content, and backend error
details are left unchanged.

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
