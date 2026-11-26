import { Component, type ErrorInfo, type ReactNode, StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./styles/gradey.css";
import { App } from "./client/App.tsx";

interface BoundaryState {
  error: Error | null;
}

class RootErrorBoundary extends Component<{ children: ReactNode }, BoundaryState> {
  state: BoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): BoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error("Gradey render error:", error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div
          className="aurora-canvas"
          style={{
            minHeight: "100vh",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: "12px",
            padding: "24px",
            textAlign: "center",
          }}
        >
          <div style={{ fontSize: "18px", fontWeight: 700 }}>Something went wrong</div>
          <div style={{ fontSize: "14px", color: "var(--text-secondary)", maxWidth: "460px" }}>
            {this.state.error.message}
          </div>
          <button
            type="button"
            className="icon-btn"
            onClick={() => window.location.reload()}
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

const rootEl = document.getElementById("root");
if (!rootEl) {
  throw new Error("Root element #root not found");
}

createRoot(rootEl).render(
  <StrictMode>
    <RootErrorBoundary>
      <App />
    </RootErrorBoundary>
  </StrictMode>,
);
