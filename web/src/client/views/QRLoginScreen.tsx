import { useCallback, useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import { webApi } from "../api.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type { PairingChallengeStatus, WebSessionSummary } from "../../shared/types.ts";
import { GradeyWordmark, Icon } from "../components/Primitives.tsx";

export type ThemeMode = "system" | "light" | "dark";

interface QRLoginScreenProps {
  locale: WebLocale;
  onChangeLocale: (locale: WebLocale) => void;
  theme: ThemeMode;
  onChangeTheme: (theme: ThemeMode) => void;
  onAuthenticated: (session: WebSessionSummary) => void;
  reauthNotice?: string | null;
}

export function QRLoginScreen({
  locale,
  onChangeLocale,
  theme,
  onChangeTheme,
  onAuthenticated,
  reauthNotice,
}: QRLoginScreenProps) {
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [qrSvg, setQrSvg] = useState<string | null>(null);
  const [expiresAtMs, setExpiresAtMs] = useState<number | null>(null);
  const [ttlSeconds, setTtlSeconds] = useState<number>(60);
  const [secondsLeft, setSecondsLeft] = useState<number>(60);
  const [status, setStatus] = useState<PairingChallengeStatus | "loading" | "claiming" | "error">(
    "loading",
  );
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const claimingRef = useRef<string | null>(null);
  const mountedRef = useRef(true);

  const t = useCallback(
    (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
      translate(locale, key, params),
    [locale],
  );

  const loadNewChallenge = useCallback(
    async (notice?: string | null) => {
      try {
        setStatus("loading");
        if (notice !== undefined) setStatusMessage(notice);
        const created = await webApi.createQRChallenge();
        if (!mountedRef.current) return;

        const svg = await QRCode.toString(created.qrPayload, {
          type: "svg",
          margin: 0,
          errorCorrectionLevel: "M",
          color: {
            dark: "#0B1211",
            light: "#FFFFFF",
          },
        });
        if (!mountedRef.current) return;

        const expMs = Date.parse(created.expiresAt);
        setChallengeId(created.challengeId);
        setQrSvg(svg);
        setExpiresAtMs(expMs);
        setTtlSeconds(created.ttlSeconds || 60);
        setSecondsLeft(Math.max(1, Math.ceil((expMs - Date.now()) / 1000)));
        setStatus("pending");
      } catch {
        if (!mountedRef.current) return;
        setStatus("error");
      }
    },
    [],
  );

  const claimApprovedChallenge = useCallback(
    async (id: string) => {
      if (claimingRef.current === id) return;
      claimingRef.current = id;
      setStatus("claiming");
      try {
        const res = await webApi.claimQRChallenge(id);
        if (!mountedRef.current) return;
        onAuthenticated(res.session);
      } catch {
        claimingRef.current = null;
        if (mountedRef.current) {
          void loadNewChallenge(null);
        }
      }
    },
    [loadNewChallenge, onAuthenticated],
  );

  useEffect(() => {
    mountedRef.current = true;
    void loadNewChallenge(reauthNotice ?? null);
    return () => {
      mountedRef.current = false;
    };
  }, [loadNewChallenge, reauthNotice]);

  // Subscribe via SSE with automatic polling fallback so pairing works across all proxies
  useEffect(() => {
    if (!challengeId || (status !== "pending" && status !== "scanned")) return;

    let pollTimer: ReturnType<typeof setInterval> | null = null;
    const handleRemoteStatus = (nextStatus: PairingChallengeStatus) => {
      if (!mountedRef.current) return;
      if (nextStatus === "scanned") {
        setStatus("scanned");
      } else if (nextStatus === "approved") {
        void claimApprovedChallenge(challengeId);
      } else if (nextStatus === "rejected") {
        void loadNewChallenge(t("login.rejected"));
      } else if (nextStatus === "expired") {
        void loadNewChallenge(null);
      }
    };

    const startPollingFallback = () => {
      if (pollTimer) return;
      pollTimer = setInterval(async () => {
        try {
          const polled = await webApi.pollQRChallenge(challengeId);
          handleRemoteStatus(polled.status);
        } catch {
          // Handled by countdown auto-regeneration
        }
      }, 2000);
    };

    const unsubscribeSse = webApi.subscribeQRChallenge(
      challengeId,
      handleRemoteStatus,
      startPollingFallback,
    );

    return () => {
      unsubscribeSse();
      if (pollTimer) clearInterval(pollTimer);
    };
  }, [challengeId, status, claimApprovedChallenge, loadNewChallenge, t]);

  // 60-second countdown & automatic regeneration
  useEffect(() => {
    if (!expiresAtMs || (status !== "pending" && status !== "scanned")) return;

    const timer = setInterval(() => {
      const remaining = Math.ceil((expiresAtMs - Date.now()) / 1000);
      if (remaining <= 0) {
        clearInterval(timer);
        void loadNewChallenge(null);
      } else {
        setSecondsLeft(remaining);
      }
    }, 500);

    return () => clearInterval(timer);
  }, [expiresAtMs, status, loadNewChallenge]);

  const progressPct = Math.min(100, Math.max(0, (secondsLeft / ttlSeconds) * 100));

  return (
    <div className="aurora-canvas auth-shell">
      <header className="auth-topbar">
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <GradeyWordmark width={118} height={32} />
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
          <div className="segmented-control" role="group" aria-label="Language">
            <button
              type="button"
              className="segmented-btn"
              data-active={locale === "en"}
              onClick={() => onChangeLocale("en")}
            >
              EN
            </button>
            <button
              type="button"
              className="segmented-btn"
              data-active={locale === "cs"}
              onClick={() => onChangeLocale("cs")}
            >
              CS
            </button>
          </div>

          <button
            type="button"
            className="icon-btn"
            onClick={() =>
              onChangeTheme(theme === "dark" ? "light" : theme === "light" ? "system" : "dark")
            }
            title={t("settings.theme")}
          >
            <Icon
              name={theme === "dark" ? "moon-02" : theme === "light" ? "sun-01" : "laptop"}
              size={15}
            />
          </button>
        </div>
      </header>

      <main className="auth-main">
        <div>
          <h1
            style={{
              fontSize: "38px",
              fontWeight: 700,
              letterSpacing: "-0.025em",
              lineHeight: 1.12,
              margin: "0 0 10px",
            }}
          >
            {t("login.heading")}
          </h1>
          <p
            style={{
              fontSize: "16px",
              color: "var(--text-secondary)",
              margin: 0,
              lineHeight: 1.5,
              maxWidth: "440px",
            }}
          >
            {t("login.subheading")}
          </p>

          <ol className="auth-steps">
            <li className="auth-step">
              <span className="auth-step-num">1</span>
              <span>{t("login.step1")}</span>
            </li>
            <li className="auth-step">
              <span className="auth-step-num">2</span>
              <span>{t("login.step2")}</span>
            </li>
            <li className="auth-step">
              <span className="auth-step-num">3</span>
              <span>{t("login.step3")}</span>
            </li>
          </ol>

          {statusMessage && (
            <div
              style={{
                marginTop: "22px",
                display: "flex",
                alignItems: "center",
                gap: "8px",
                fontSize: "13.5px",
                color: "var(--accent-orange)",
              }}
            >
              <Icon name="information-circle" size={16} />
              <span>{statusMessage}</span>
            </div>
          )}
        </div>

        <div className="qr-stage">
          <div className="qr-frame" data-testid="qr-code-container">
            {qrSvg && status !== "error" ? (
              <div
                style={{ width: "100%", height: "100%" }}
                dangerouslySetInnerHTML={{ __html: qrSvg }}
              />
            ) : null}

            {status === "loading" && (
              <div className="qr-overlay">
                <Icon name="refresh-04" size={24} className="spin" color="#17a185" />
                <div style={{ fontSize: "13.5px", fontWeight: 600 }}>{t("login.regenerating")}</div>
              </div>
            )}

            {status === "scanned" && (
              <div className="qr-overlay">
                <Icon name="laptop-phone-sync" size={28} color="#17a185" />
                <div style={{ fontSize: "15px", fontWeight: 700 }}>{t("login.scanned.title")}</div>
                <div style={{ fontSize: "13px", color: "rgba(11, 18, 17, 0.68)" }}>
                  {t("login.scanned.body")}
                </div>
              </div>
            )}

            {status === "claiming" && (
              <div className="qr-overlay">
                <Icon name="checkmark-circle-02" size={28} color="#17a185" />
                <div style={{ fontSize: "15px", fontWeight: 700 }}>{t("login.completing")}</div>
              </div>
            )}

            {status === "error" && (
              <div className="qr-overlay">
                <Icon name="alert-circle" size={26} color="#d83e4f" />
                <div style={{ fontSize: "13.5px", fontWeight: 600 }}>{t("login.error")}</div>
                <button
                  type="button"
                  className="icon-btn"
                  style={{ color: "#0b1211", borderColor: "rgba(11,18,17,0.2)" }}
                  onClick={() => void loadNewChallenge(null)}
                >
                  <Icon name="refresh-04" size={14} />
                  <span>{t("action.retry")}</span>
                </button>
              </div>
            )}
          </div>

          {(status === "pending" || status === "scanned") && (
            <div className="qr-expiry tabular" data-testid="qr-expiry-indicator">
              <div className="qr-progress-track">
                <div className="qr-progress-fill" style={{ width: `${progressPct}%` }} />
              </div>
              <span>{t("login.expiresIn", { seconds: secondsLeft })}</span>
            </div>
          )}
        </div>
      </main>

      <footer
        style={{
          maxWidth: "1040px",
          width: "100%",
          margin: "0 auto",
          display: "flex",
          alignItems: "center",
          gap: "7px",
          fontSize: "12.5px",
          color: "var(--text-tertiary)",
        }}
      >
        <Icon name="security-lock" size={14} />
        <span>{t("login.securityNote")}</span>
      </footer>
    </div>
  );
}
