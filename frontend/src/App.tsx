import DocumentIngestion from "./components/DocumentIngestion";
import QueryPanel from "./components/QueryPanel";
import LanguageSwitcher from "./components/LanguageSwitcher";
import { useTranslation } from "react-i18next";

export default function App() {
  const { t } = useTranslation();

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100 flex flex-col font-sans">
      <header className="border-b border-slate-800 bg-slate-950/70 backdrop-blur px-6 py-4 flex flex-wrap gap-4 items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-indigo-600 flex items-center justify-center font-bold">
            R
          </div>
          <h1 className="text-xl font-bold tracking-tight">{t("app.title")}</h1>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <span className="text-xs bg-slate-800 text-slate-400 border border-slate-700 px-3 py-1 rounded-full">
            {t("app.technology")}
          </span>
          <LanguageSwitcher />
        </div>
      </header>

      <main className="flex-1 max-w-7xl w-full mx-auto p-6 grid grid-cols-1 md:grid-cols-3 gap-6">
        <DocumentIngestion />
        <QueryPanel />
      </main>
    </div>
  );
}
