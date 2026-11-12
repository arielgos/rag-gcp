import i18n from "./i18n";

export const API_BASE_URL =
  import.meta.env.VITE_API_URL || "http://localhost:8080";

interface IngestResponse {
  status: string;
  document_name: string;
  chunks_indexed: number;
}

export interface Citation {
  file_path: string;
  document_name: string;
  content: string;
  score: number;
  download_url: string | null;
}

export interface QueryResponse {
  answer: string;
  citations: Citation[];
}

interface ApiError {
  detail?: unknown;
}

type RequestErrorKey = "errors.uploadFailed" | "errors.queryFailed";

class ApiRequestError extends Error {
  readonly translationKey: RequestErrorKey | null;

  constructor(key: RequestErrorKey, detail: unknown) {
    super(typeof detail === "string" ? detail : i18n.t(key));
    this.translationKey = typeof detail === "string" ? null : key;
  }
}

export function getErrorMessage(error: unknown): string {
  if (error instanceof ApiRequestError && error.translationKey) {
    return i18n.t(error.translationKey);
  }
  return error instanceof Error ? error.message : String(error);
}

export async function ingestDocument(file: File): Promise<IngestResponse> {
  const formData = new FormData();
  formData.append("file", file);

  const res = await fetch(`${API_BASE_URL}/ingest`, {
    method: "POST",
    body: formData,
  });

  if (!res.ok) {
    const error: ApiError = await res.json();
    throw new ApiRequestError("errors.uploadFailed", error.detail);
  }

  return res.json();
}

export async function queryDocuments(query: string): Promise<QueryResponse> {
  const res = await fetch(`${API_BASE_URL}/query`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query,
      language: i18n.resolvedLanguage === "es" ? "es" : "en",
      top_candidates: 25,
      top_reranked: 4,
    }),
  });

  if (!res.ok) {
    const error: ApiError = await res.json();
    throw new ApiRequestError("errors.queryFailed", error.detail);
  }

  return res.json();
}
