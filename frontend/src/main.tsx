import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { initializeI18n } from "./i18n";
import "./index.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("Root element #root was not found.");
}

initializeI18n()
  .then(() => {
    ReactDOM.createRoot(root).render(
      <React.StrictMode>
        <App />
      </React.StrictMode>,
    );
  })
  .catch((error: unknown) => {
    console.error("Could not initialize translations.", error);
    root.textContent = "Unable to initialize the application. Please reload.";
  });
