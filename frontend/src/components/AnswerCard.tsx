import { useState } from "react";
import ReactMarkdown from "react-markdown";
import type { QueryResponse } from "../api";
import CitationCard from "./CitationCard";
import { useTranslation } from "react-i18next";

interface AnswerCardProps {
  result: QueryResponse | null;
}

export default function AnswerCard({ result }: AnswerCardProps) {
  const { t } = useTranslation();
  const [openCitation, setOpenCitation] = useState<number | null>(null);

  if (!result) return null;

  return (
    <div className="bg-slate-800/40 border border-slate-800 rounded-2xl p-6 space-y-6">
      <div>
        <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-400 mb-2">
          {t("answer.title")}
        </h3>
        <div className="prose prose-invert max-w-none text-slate-200 text-base leading-relaxed">
          <ReactMarkdown>{result.answer}</ReactMarkdown>
        </div>
      </div>

      {result.citations && result.citations.length > 0 && (
        <div className="border-t border-slate-800 pt-4">
          <h4 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
            {t("answer.sources", { count: result.citations.length })}
          </h4>
          <div className="space-y-2">
            {result.citations.map((citation, index) => (
              <CitationCard
                key={index}
                citation={citation}
                index={index}
                isOpen={openCitation === index}
                onToggle={() =>
                  setOpenCitation(openCitation === index ? null : index)
                }
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
