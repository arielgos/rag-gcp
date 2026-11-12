import { useTranslation } from "react-i18next";
import { ChevronDown } from "lucide-react";

export default function LanguageSwitcher() {
  const { t, i18n } = useTranslation();

  return (
    <label className="inline-flex items-center gap-2 text-xs bg-slate-800 text-slate-400 border border-slate-700 px-3 py-1 rounded-full focus-within:ring-2 focus-within:ring-indigo-500">
      <span>{t("app.language")}</span>
      <select
        aria-label={t("app.language")}
        value={i18n.resolvedLanguage || "en"}
        onChange={(event) => {
          i18n
            .changeLanguage(event.currentTarget.value)
            .catch((error: unknown) => {
              console.error("Could not change language.", error);
              alert(t("errors.languageChangeFailed"));
            });
        }}
        className="cursor-pointer appearance-none bg-transparent p-0 text-inherit focus:outline-none"
      >
        <option value="en" lang="en">
          {t("languages.en")}
        </option>
        <option value="es" lang="es">
          {t("languages.es")}
        </option>
      </select>
      <ChevronDown className="w-3 h-3 pointer-events-none" aria-hidden="true" />
    </label>
  );
}
