import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./styles/gradey.css";
import { App } from "./client/App.tsx";

const rootEl = document.getElementById("root");
if (!rootEl) {
  throw new Error("Root element #root not found");
}

createRoot(rootEl).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
