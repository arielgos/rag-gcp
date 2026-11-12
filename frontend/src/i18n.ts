import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import { initReactI18next } from "react-i18next";
import en from "./locales/en.json";
import es from "./locales/es.json";

function updateDocumentLanguage() {
  document.documentElement.lang = i18n.resolvedLanguage || "en";
  document.title = i18n.t("app.title");
}

export async function initializeI18n() {
  await i18n
    .use(LanguageDetector)
    .use(initReactI18next)
    .init({
      resources: {
        en: { translation: en },
        es: { translation: es satisfies typeof en },
      },
      supportedLngs: ["en", "es"],
      fallbackLng: "en",
      load: "languageOnly",
      detection: {
        order: ["localStorage", "navigator"],
        lookupLocalStorage: "rag-language",
        caches: ["localStorage"],
      },
      interpolation: {
        escapeValue: false,
      },
    });

  i18n.on("languageChanged", updateDocumentLanguage);
  updateDocumentLanguage();
}

export default i18n;
