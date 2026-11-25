import { translate, type WebLocale } from "../../shared/i18n.ts";
import type { UserProfile, WebSessionSummary } from "../../shared/types.ts";
import { formatDateTime, Icon, PlainSection } from "../components/Primitives.tsx";
import type { ThemeMode } from "./QRLoginScreen.tsx";

interface SettingsSectionViewProps {
  user: UserProfile | null;
  session: WebSessionSummary;
  locale: WebLocale;
  onChangeLocale: (locale: WebLocale) => void;
  theme: ThemeMode;
  onChangeTheme: (theme: ThemeMode) => void;
  onLogout: () => void;
  isLoggingOut: boolean;
}

export function SettingsSectionView({
  user,
  session,
  locale,
  onChangeLocale,
  theme,
  onChangeTheme,
  onLogout,
  isLoggingOut,
}: SettingsSectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  return (
    <div className="page-scroll" style={{ maxWidth: "680px" }}>
      {/* School Profile */}
      <PlainSection title={t("settings.studentSection")}>
        <ValueRow label={t("settings.studentName")} value={user?.fullName ?? session.studentName} />
        {(user?.userClass?.abbrev || session.className) && (
          <ValueRow
            label={t("settings.class")}
            value={user?.userClass?.abbrev ?? session.className ?? ""}
          />
        )}
        {(user?.schoolName || session.schoolName) && (
          <ValueRow
            label={t("settings.school")}
            value={user?.schoolName ?? session.schoolName ?? ""}
          />
        )}
        {user?.userTypeText && (
          <ValueRow label={t("settings.role")} value={user.userTypeText} />
        )}
        {user?.studyYear != null && (
          <ValueRow label={t("settings.studyYear")} value={String(user.studyYear)} />
        )}
        <ValueRow
          label={t("settings.provider")}
          value={session.provider === "eduPage" ? "EduPage" : "Bakaláři"}
        />
      </PlainSection>

      {/* Active Web Session */}
      <PlainSection title={t("settings.sessionSection")}>
        <ValueRow label={t("settings.device")} value={session.browserName} />
        <ValueRow label={t("settings.os")} value={session.osName} />
        <ValueRow
          label={t("settings.firstLogin")}
          value={formatDateTime(session.firstLoginAt, locale)}
          tabular
        />
        <ValueRow
          label={t("settings.lastActive")}
          value={formatDateTime(session.lastActiveAt, locale)}
          tabular
        />
      </PlainSection>
      <div
        style={{
          marginTop: "10px",
          fontSize: "12.5px",
          color: "var(--text-secondary)",
          display: "flex",
          alignItems: "flex-start",
          gap: "7px",
        }}
      >
        <Icon name="laptop-phone-sync" size={15} color="var(--brand-primary)" />
        <span>{t("settings.sessionNote")}</span>
      </div>

      {/* Appearance & Language */}
      <PlainSection title={t("settings.preferencesSection")}>
        <div className="plain-row">
          <span>{t("settings.theme")}</span>
          <div className="segmented-control">
            {(["system", "light", "dark"] as const).map((mode) => (
              <button
                key={mode}
                type="button"
                className="segmented-btn"
                data-active={theme === mode}
                onClick={() => onChangeTheme(mode)}
              >
                {t(`settings.theme.${mode}`)}
              </button>
            ))}
          </div>
        </div>

        <div className="plain-row">
          <span>{t("settings.language")}</span>
          <div className="segmented-control">
            <button
              type="button"
              className="segmented-btn"
              data-active={locale === "en"}
              onClick={() => onChangeLocale("en")}
            >
              English
            </button>
            <button
              type="button"
              className="segmented-btn"
              data-active={locale === "cs"}
              onClick={() => onChangeLocale("cs")}
            >
              Čeština
            </button>
          </div>
        </div>
      </PlainSection>

      {/* Sign out */}
      <div style={{ marginTop: "32px" }}>
        <button
          type="button"
          className="icon-btn"
          disabled={isLoggingOut}
          onClick={onLogout}
          style={{
            color: "var(--band-poor)",
            borderColor: "rgba(216, 62, 79, 0.3)",
            padding: "10px 18px",
            fontSize: "14px",
          }}
          data-testid="logout-button"
        >
          <Icon name="logout-01" size={16} color="var(--band-poor)" />
          <span>{t("action.logout")}</span>
        </button>
      </div>
    </div>
  );
}

function ValueRow({
  label,
  value,
  tabular = false,
}: {
  label: string;
  value: string;
  tabular?: boolean;
}) {
  return (
    <div className="plain-row">
      <span style={{ color: "var(--text-secondary)" }}>{label}</span>
      <span className={tabular ? "tabular" : undefined} style={{ fontWeight: 600 }}>
        {value}
      </span>
    </div>
  );
}
