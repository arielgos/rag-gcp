import { ChevronDown, ChevronUp, Download } from "lucide-react";
import { API_BASE_URL } from "../api";
import type { Citation } from "../api";
import { useTranslation } from "react-i18next";

interface CitationCardProps {
  citation: Citation;
  index: number;
  isOpen: boolean;
  onToggle: () => void;
}

export default function CitationCard({
  citation,
  index,
  isOpen,
  onToggle,
}: CitationCardProps) {
  const { t, i18n } = useTranslation();

  return (
    <div className="border border-slate-700/60 rounded-lg overflow-hidden bg-slate-900/40">
      <button
        onClick={onToggle}
        className="w-full px-4 py-2.5 text-left text-sm flex items-center justify-between hover:bg-slate-800/50 transition"
      >
        <div className="flex items-center gap-2 truncate">
          <span className="font-semibold text-indigo-400">#{index + 1}</span>
          <span className="font-mono text-xs text-slate-300 truncate">
            {citation.file_path}
          </span>
          <span className="text-xs bg-slate-800 text-slate-400 px-2 py-0.5 rounded ml-2">
            {t("citation.score", {
              score: new Intl.NumberFormat(i18n.resolvedLanguage, {
                minimumFractionDigits: 3,
                maximumFractionDigits: 3,
              }).format(citation.score),
            })}
          </span>
        </div>
        {isOpen ? (
          <ChevronUp className="w-4 h-4 text-slate-400" />
        ) : (
          <ChevronDown className="w-4 h-4 text-slate-400" />
        )}
      </button>

      <div className="px-4 pb-3">
        {citation.download_url ? (
          <a
            href={`${API_BASE_URL}${citation.download_url}`}
            download={citation.document_name}
            className="inline-flex items-center gap-2 text-sm text-indigo-300 hover:text-indigo-200"
          >
            <Download className="w-4 h-4" />
            {t("citation.download")}
          </a>
        ) : (
          <p className="text-xs text-slate-400">{t("citation.unavailable")}</p>
        )}
      </div>

      {isOpen && (
        <div className="p-4 bg-slate-950/60 border-t border-slate-800/60 text-xs text-slate-300 font-mono whitespace-pre-wrap max-h-48 overflow-y-auto">
          {citation.content}
        </div>
      )}
    </div>
  );
}
