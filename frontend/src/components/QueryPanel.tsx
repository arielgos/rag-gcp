import { useState } from "react";
import type { FormEvent } from "react";
import { Send, Loader2 } from "lucide-react";
import { getErrorMessage, queryDocuments } from "../api";
import type { QueryResponse } from "../api";
import AnswerCard from "./AnswerCard";
import { useTranslation } from "react-i18next";

export default function QueryPanel() {
  const { t } = useTranslation();
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<QueryResponse | null>(null);

  const handleQuery = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!query.trim()) return;

    setLoading(true);
    setResult(null);

    try {
      setResult(await queryDocuments(query));
    } catch (err) {
      alert(
        t("errors.query", {
          message: getErrorMessage(err),
        }),
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="md:col-span-2 flex flex-col gap-6">
      <form onSubmit={handleQuery} className="flex gap-2">
        <input
          type="text"
          placeholder={t("query.placeholder")}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="flex-1 bg-slate-800/80 border border-slate-700 rounded-xl px-4 py-3 text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        />
        <button
          type="submit"
          aria-label={loading ? t("query.loading") : t("query.submit")}
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

      <AnswerCard result={result} />
    </section>
  );
}
