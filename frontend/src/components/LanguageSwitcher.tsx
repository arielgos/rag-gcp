import { useTranslation } from "react-i18next";

export default function LanguageSwitcher() {
  const { t, i18n } = useTranslation();

  return (
    <label className="flex items-center gap-2 text-sm text-slate-300">
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
        className="rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-slate-100"
      >
        <option value="en" lang="en">
          {t("languages.en")}
        </option>
        <option value="es" lang="es">
          {t("languages.es")}
        </option>
      </select>
    </label>
  );
}
