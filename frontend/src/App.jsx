import React, { useState } from "react";
import ReactMarkdown from "react-markdown";
import {
  UploadCloud,
  Send,
  FileText,
  CheckCircle2,
  AlertCircle,
  Loader2,
  ChevronDown,
  ChevronUp,
  Download,
} from "lucide-react";

// Read API URL from environment variable, fallback to localhost
const API_BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:8080";

export default function App() {
  // Ingest state
  const [selectedFile, setSelectedFile] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [uploadMessage, setUploadMessage] = useState(null);

  // Query state
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [openCitation, setOpenCitation] = useState(null);

  // Handle File Ingestion
  const handleFileUpload = async (e) => {
    e.preventDefault();
    if (!selectedFile) return;

    setUploading(true);
    setUploadMessage(null);

    const formData = new FormData();
    formData.append("file", selectedFile);

    try {
      const res = await fetch(`${API_BASE_URL}/ingest`, {
        method: "POST",
        body: formData,
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Upload failed");

      setUploadMessage({
        type: "success",
        text: `Indexed "${data.document_name}" successfully (${data.chunks_indexed} chunks created).`,
      });
      setSelectedFile(null);
    } catch (err) {
      setUploadMessage({ type: "error", text: err.message });
    } finally {
      setUploading(false);
    }
  };

  // Handle RAG Query
  const handleQuery = async (e) => {
    e.preventDefault();
    if (!query.trim()) return;

    setLoading(true);
    setResult(null);

    try {
      const res = await fetch(`${API_BASE_URL}/query`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: query,
          top_candidates: 25,
          top_reranked: 4,
        }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Query failed");
      setResult(data);
    } catch (err) {
      alert("Error: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100 flex flex-col font-sans">
      {/* Header */}
      <header className="border-b border-slate-800 bg-slate-950/70 backdrop-blur px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-indigo-600 flex items-center justify-center font-bold">
            R
          </div>
          <h1 className="text-xl font-bold tracking-tight">
            MarkItDown + Gemini RAG
          </h1>
        </div>
        <span className="text-xs bg-slate-800 text-slate-400 border border-slate-700 px-3 py-1 rounded-full">
          Cloud SQL (pgvector) + FlashRank
        </span>
      </header>

      {/* Main Grid */}
      <main className="flex-1 max-w-7xl w-full mx-auto p-6 grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Left Column: Upload / Ingestion */}
        <section className="bg-slate-800/40 border border-slate-800 p-6 rounded-2xl flex flex-col gap-4 h-fit">
          <div className="flex items-center gap-2">
            <UploadCloud className="text-indigo-400 w-5 h-5" />
            <h2 className="text-lg font-semibold">Document Ingestion</h2>
          </div>
          <p className="text-sm text-slate-400">
            Upload any file (
            <code className="text-indigo-300">PDF, DOCX, XLSX, PPTX</code>).
            MarkItDown will parse it into markdown, embed it with Gemini, and
            index it into Postgres.
          </p>

          <form onSubmit={handleFileUpload} className="space-y-4">
            <label className="border-2 border-dashed border-slate-700 hover:border-indigo-500 hover:bg-slate-800/60 transition duration-150 rounded-xl p-6 flex flex-col items-center justify-center cursor-pointer">
              <FileText className="w-8 h-8 text-slate-400 mb-2" />
              <span className="text-sm text-slate-300 font-medium">
                {selectedFile ? selectedFile.name : "Select a document"}
              </span>
              <span className="text-xs text-slate-500 mt-1">Up to 32MB</span>
              <input
                type="file"
                className="hidden"
                onChange={(e) => setSelectedFile(e.target.files[0])}
              />
            </label>

            <button
              type="submit"
              disabled={!selectedFile || uploading}
              className="w-full flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-slate-700 text-white font-medium py-2.5 px-4 rounded-xl transition duration-150"
            >
              {uploading ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                "Ingest Document"
              )}
            </button>
          </form>

          {uploadMessage && (
            <div
              className={`p-3 rounded-lg text-sm flex items-start gap-2.5 ${
                uploadMessage.type === "success"
                  ? "bg-emerald-950/60 border border-emerald-800 text-emerald-300"
                  : "bg-rose-950/60 border border-rose-800 text-rose-300"
              }`}
            >
              {uploadMessage.type === "success" ? (
                <CheckCircle2 className="w-5 h-5 flex-shrink-0" />
              ) : (
                <AlertCircle className="w-5 h-5 flex-shrink-0" />
              )}
              <span>{uploadMessage.text}</span>
            </div>
          )}
        </section>

        {/* Right Column: Query & Response */}
        <section className="md:col-span-2 flex flex-col gap-6">
          {/* Query Bar */}
          <form onSubmit={handleQuery} className="flex gap-2">
            <input
              type="text"
              placeholder="Ask a question about your uploaded documents..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="flex-1 bg-slate-800/80 border border-slate-700 rounded-xl px-4 py-3 text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
            <button
              type="submit"
              disabled={loading || !query.trim()}
              className="bg-indigo-600 hover:bg-indigo-500 disabled:bg-slate-700 text-white px-5 rounded-xl flex items-center justify-center font-medium transition"
            >
              {loading ? (
                <Loader2 className="w-5 h-5 animate-spin" />
              ) : (
                <Send className="w-5 h-5" />
              )}
            </button>
          </form>

          {/* Answer Card */}
          {result && (
            <div className="bg-slate-800/40 border border-slate-800 rounded-2xl p-6 space-y-6">
              <div>
                <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-400 mb-2">
                  Gemini Answer
                </h3>
                <div className="prose prose-invert max-w-none text-slate-200 text-base leading-relaxed">
                  <ReactMarkdown>{result.answer}</ReactMarkdown>
                </div>
              </div>

              {/* Citations / Sources */}
              {result.citations && result.citations.length > 0 && (
                <div className="border-t border-slate-800 pt-4">
                  <h4 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
                    Reranked Sources & Citations ({result.citations.length})
                  </h4>
                  <div className="space-y-2">
                    {result.citations.map((cite, idx) => (
                      <div
                        key={idx}
                        className="border border-slate-700/60 rounded-lg overflow-hidden bg-slate-900/40"
                      >
                        <button
                          onClick={() =>
                            setOpenCitation(openCitation === idx ? null : idx)
                          }
                          className="w-full px-4 py-2.5 text-left text-sm flex items-center justify-between hover:bg-slate-800/50 transition"
                        >
                          <div className="flex items-center gap-2 truncate">
                            <span className="font-semibold text-indigo-400">
                              #{idx + 1}
                            </span>
                            <span className="font-mono text-xs text-slate-300 truncate">
                              {cite.file_path}
                            </span>
                            <span className="text-xs bg-slate-800 text-slate-400 px-2 py-0.5 rounded ml-2">
                              Score: {cite.score.toFixed(3)}
                            </span>
                          </div>
                          {openCitation === idx ? (
                            <ChevronUp className="w-4 h-4 text-slate-400" />
                          ) : (
                            <ChevronDown className="w-4 h-4 text-slate-400" />
                          )}
                        </button>

                        <div className="px-4 pb-3">
                          {cite.download_url ? (
                            <a
                              href={`${API_BASE_URL}${cite.download_url}`}
                              download={cite.document_name}
                              className="inline-flex items-center gap-2 text-sm text-indigo-300 hover:text-indigo-200"
                            >
                              <Download className="w-4 h-4" />
                              Download original document
                            </a>
                          ) : (
                            <p className="text-xs text-slate-400">
                              Original unavailable. Re-upload this document to enable downloads.
                            </p>
                          )}
                        </div>

                        {openCitation === idx && (
                          <div className="p-4 bg-slate-950/60 border-t border-slate-800/60 text-xs text-slate-300 font-mono whitespace-pre-wrap max-h-48 overflow-y-auto">
                            {cite.content}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
