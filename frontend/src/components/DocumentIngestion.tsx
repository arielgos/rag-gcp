import { useState } from "react";
import type { FormEvent } from "react";
import {
  UploadCloud,
  FileText,
  CheckCircle2,
  AlertCircle,
  Loader2,
} from "lucide-react";
import { getErrorMessage, ingestDocument } from "../api";
import { Trans, useTranslation } from "react-i18next";

type UploadMessage =
  | { type: "success"; documentName: string; count: number }
  | { type: "error"; error: unknown };

export default function DocumentIngestion() {
  const { t } = useTranslation();
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadMessage, setUploadMessage] = useState<UploadMessage | null>(
    null,
  );

  const handleFileUpload = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!selectedFile) return;

    setUploading(true);
    setUploadMessage(null);

    try {
      const data = await ingestDocument(selectedFile);
      setUploadMessage({
        type: "success",
        documentName: data.document_name,
        count: data.chunks_indexed,
      });
      setSelectedFile(null);
    } catch (err) {
      setUploadMessage({
        type: "error",
        error: err,
      });
    } finally {
      setUploading(false);
    }
  };

  return (
    <section className="bg-slate-800/40 border border-slate-800 p-6 rounded-2xl flex flex-col gap-4 h-fit">
      <div className="flex items-center gap-2">
        <UploadCloud className="text-indigo-400 w-5 h-5" />
        <h2 className="text-lg font-semibold">{t("upload.title")}</h2>
      </div>
      <p className="text-sm text-slate-400">
        <Trans
          i18nKey="upload.description"
          components={{ formats: <code className="text-indigo-300" /> }}
        />
      </p>

      <form onSubmit={handleFileUpload} className="space-y-4">
        <label className="border-2 border-dashed border-slate-700 hover:border-indigo-500 hover:bg-slate-800/60 transition duration-150 rounded-xl p-6 flex flex-col items-center justify-center cursor-pointer">
          <FileText className="w-8 h-8 text-slate-400 mb-2" />
          <span className="text-sm text-slate-300 font-medium">
            {selectedFile ? selectedFile.name : t("upload.selectDocument")}
          </span>
          <span className="text-xs text-slate-500 mt-1">
            {t("upload.sizeLimit")}
          </span>
          <input
            type="file"
            aria-label={t("upload.selectDocument")}
            className="hidden"
            onChange={(e) =>
              setSelectedFile(e.currentTarget.files?.[0] ?? null)
            }
          />
        </label>

        <button
          type="submit"
          aria-label={uploading ? t("upload.uploading") : t("upload.submit")}
          disabled={!selectedFile || uploading}
          className="w-full flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-slate-700 text-white font-medium py-2.5 px-4 rounded-xl transition duration-150"
        >
          {uploading ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            t("upload.submit")
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
          <span>
            {uploadMessage.type === "success"
              ? t("upload.success", {
                  documentName: uploadMessage.documentName,
                  count: uploadMessage.count,
                })
              : getErrorMessage(uploadMessage.error)}
          </span>
        </div>
      )}
    </section>
  );
}
