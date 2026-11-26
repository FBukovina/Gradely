import { useEffect, useState, type ReactNode } from "react";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import { parseStudentDisplayName } from "../../shared/schoolMath.ts";
import type { UserProfile, WebSessionSummary } from "../../shared/types.ts";
import { formatDateTime, Icon } from "../components/Primitives.tsx";
import type { ThemeMode } from "./QRLoginScreen.tsx";

type SettingsDestination = "account" | "session" | "privacy" | "preferences" | "about";

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

const HELP_HOST = "https://help.bukovinafilip.com";
const GITHUB_REPO_URL = "https://github.com/FBukovina/Gradely";
const DEVELOPER_EMAIL = "filip@openside.tech";

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
  const [destination, setDestination] = useState<SettingsDestination>("account");
  const [confirmingLogout, setConfirmingLogout] = useState(false);

  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  useEffect(() => {
    if (!confirmingLogout) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !isLoggingOut) {
        setConfirmingLogout(false);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [confirmingLogout, isLoggingOut]);

  const classAbbrev = user?.userClass?.abbrev ?? session.className ?? null;
  const schoolName = user?.schoolName ?? session.schoolName ?? null;
  const providerLabel = session.provider === "eduPage" ? "EduPage" : "Bakaláři";

  const parsedStudent = parseStudentDisplayName(
    user?.fullName ?? session.studentName,
    classAbbrev,
    session.provider,
  );

  const profileSubtitleParts = [classAbbrev, providerLabel].filter(Boolean);
  const profileSubtitle = profileSubtitleParts.join(" · ");

  const activeLanguageLabel = locale === "cs" ? "Čeština" : "English";
  const activeThemeLabel = t(`settings.theme.${theme}`);
  const helpLang = locale === "cs" ? "cs" : "en";
  const privacyPolicyURL = `${HELP_HOST}/${helpLang}/articles/10-privacy-policy`;
  const termsOfUseURL = `${HELP_HOST}/${helpLang}/articles/11-terms-and-conditions`;
  const helpCenterURL = `${HELP_HOST}/${helpLang}`;

  const deviceIcon = session.osName.toLowerCase().includes("ios")
    ? "smart-phone-01"
    : "laptop";

  return (
    <div className="settings-hub-split">
      {/* Left column: GradelyMac Settings source-list / overview */}
      <aside className="settings-hub-master" aria-label={t("nav.settings")}>
        <div className="settings-surface settings-surface-flush">
          <button
            type="button"
            className="settings-profile-button"
            data-selected={destination === "account"}
            onClick={() => setDestination("account")}
          >
            <div className="settings-avatar settings-avatar-md" aria-hidden="true">
              {parsedStudent.initials || <Icon name="user" size={18} />}
            </div>
            <div className="settings-nav-copy">
              <span className="settings-profile-name">{parsedStudent.fullName}</span>
              <span className="settings-nav-subtitle">{profileSubtitle}</span>
            </div>
            <Icon name="arrow-right-01" size={14} className="settings-disclosure" />
          </button>
        </div>

        <div className="settings-master-group">
          <div className="settings-surface settings-surface-flush">
            <SettingsOverviewRow
              icon="laptop-phone-sync"
              title={t("settings.dest.session")}
              subtitle={`${session.browserName} · ${session.osName}`}
              statusDot
              selected={destination === "session"}
              onSelect={() => setDestination("session")}
            />
            <div className="settings-row-divider settings-row-divider-indented" />
            <SettingsOverviewRow
              icon="security-lock"
              title={t("settings.dest.privacy")}
              subtitle={t("settings.privacy.subtitle")}
              selected={destination === "privacy"}
              onSelect={() => setDestination("privacy")}
            />
          </div>
        </div>

        <div className="settings-master-group">
          <div className="settings-group-label">{t("settings.group.app")}</div>
          <div className="settings-surface settings-surface-flush">
            <SettingsOverviewRow
              icon="settings-02"
              title={t("settings.dest.preferences")}
              subtitle={`${activeLanguageLabel} · ${activeThemeLabel}`}
              selected={destination === "preferences"}
              onSelect={() => setDestination("preferences")}
            />
            <div className="settings-row-divider settings-row-divider-indented" />
            <SettingsOverviewRow
              icon="help-circle"
              title={t("settings.dest.about")}
              subtitle={t("app.webSubtitle")}
              selected={destination === "about"}
              onSelect={() => setDestination("about")}
            />
          </div>
        </div>
      </aside>

      {/* Right column: Selected destination detail */}
      <div className="settings-hub-detail">
        {destination === "account" && (
          <div className="settings-detail-stack">
            {/* Profile Hero */}
            <div className="settings-account-hero">
              <div className="settings-avatar settings-avatar-lg" aria-hidden="true">
                {parsedStudent.initials || <Icon name="user" size={22} />}
              </div>
              <div className="settings-account-hero-body">
                <div className="settings-account-hero-title-row">
                  <h2 className="settings-account-hero-name">{parsedStudent.fullName}</h2>
                  <span className="settings-active-pill">
                    <Icon name="tick-02" size={12} />
                    <span>{providerLabel}</span>
                  </span>
                </div>
                {(classAbbrev || schoolName) && (
                  <p className="settings-account-hero-sub">
                    {[classAbbrev, schoolName].filter(Boolean).join(" · ")}
                  </p>
                )}
              </div>
            </div>

            {/* Connected School Details */}
            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.studentSection")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsValueRow
                  label={t("settings.studentName")}
                  value={parsedStudent.fullName}
                />
                {classAbbrev && (
                  <>
                    <div className="settings-row-divider" />
                    <SettingsValueRow label={t("settings.class")} value={classAbbrev} />
                  </>
                )}
                {schoolName && (
                  <>
                    <div className="settings-row-divider" />
                    <SettingsValueRow label={t("settings.school")} value={schoolName} multiline />
                  </>
                )}
                {user?.userTypeText && (
                  <>
                    <div className="settings-row-divider" />
                    <SettingsValueRow label={t("settings.role")} value={user.userTypeText} />
                  </>
                )}
                {user?.studyYear != null && (
                  <>
                    <div className="settings-row-divider" />
                    <SettingsValueRow
                      label={t("settings.studyYear")}
                      value={String(user.studyYear)}
                      tabular
                    />
                  </>
                )}
                <div className="settings-row-divider" />
                <SettingsValueRow label={t("settings.provider")} value={providerLabel} />
              </div>
            </section>

            {/* Quick session & destructive sign-out group (matches GradeyAccountHubView accountDetail) */}
            <section className="settings-section-block">
              <div className="settings-surface settings-surface-flush">
                <SettingsActionRow
                  icon="laptop-phone-sync"
                  title={t("settings.account.sessionRowTitle")}
                  subtitle={`${session.browserName} · ${session.osName}`}
                  onClick={() => setDestination("session")}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsActionRow
                  icon="logout-01"
                  title={t("settings.account.logoutRowTitle")}
                  subtitle={t("settings.account.logoutRowSubtitle")}
                  destructive
                  accessory="none"
                  disabled={isLoggingOut}
                  onClick={() => setConfirmingLogout(true)}
                  testId="logout-button"
                />
              </div>
            </section>
          </div>
        )}

        {destination === "session" && (
          <div className="settings-detail-stack">
            <div className="settings-hero-note">
              <div className="settings-hero-note-heading">
                <Icon name="laptop-phone-sync" size={21} color="var(--brand-primary)" />
                <h2>{t("settings.session.heroTitle")}</h2>
              </div>
              <p>{t("settings.session.heroBody")}</p>
            </div>

            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.sessionSection")}</h3>
              <div className="settings-surface settings-surface-flush">
                <div className="settings-device-lead">
                  <SettingsIcon name={deviceIcon} />
                  <div className="settings-nav-copy">
                    <span className="settings-row-title">{session.browserName}</span>
                    <span className="settings-nav-subtitle">
                      {[session.osName, schoolName ?? parsedStudent.fullName]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </div>
                  <span className="settings-active-pill">
                    <Icon name="checkmark-circle-02" size={13} />
                    <span>{t("settings.session.currentBadge")}</span>
                  </span>
                </div>

                <div className="settings-row-divider" />
                <SettingsValueRow label={t("settings.device")} value={session.browserName} />
                <div className="settings-row-divider" />
                <SettingsValueRow label={t("settings.os")} value={session.osName} />
                <div className="settings-row-divider" />
                <SettingsValueRow
                  label={t("settings.firstLogin")}
                  value={formatDateTime(session.firstLoginAt, locale)}
                  tabular
                />
                <div className="settings-row-divider" />
                <SettingsValueRow
                  label={t("settings.lastActive")}
                  value={formatDateTime(session.lastActiveAt, locale)}
                  tabular
                />
                <div className="settings-row-divider" />
                <SettingsValueRow
                  label={t("settings.session.authMethod")}
                  value={t("settings.session.authMethodValue")}
                />
              </div>
            </section>

            <SettingsFootnote icon="smart-phone-01" text={t("settings.sessionNote")} />

            <section className="settings-section-block">
              <div className="settings-surface settings-surface-flush">
                <SettingsActionRow
                  icon="logout-01"
                  title={t("settings.account.logoutRowTitle")}
                  destructive
                  accessory="none"
                  disabled={isLoggingOut}
                  onClick={() => setConfirmingLogout(true)}
                  testId="logout-button"
                />
              </div>
            </section>
          </div>
        )}

        {destination === "privacy" && (
          <div className="settings-detail-stack">
            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.privacy.securitySection")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsFeatureRow
                  icon="security-check"
                  title={t("settings.privacy.zeroPasswords.title")}
                  description={t("settings.privacy.zeroPasswords.body")}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsFeatureRow
                  icon="key-01"
                  title={t("settings.privacy.isolatedTokens.title")}
                  description={t("settings.privacy.isolatedTokens.body")}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsFeatureRow
                  icon="view"
                  title={t("settings.privacy.readOnly.title")}
                  description={t("settings.privacy.readOnly.body")}
                />
              </div>
            </section>

            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.privacy.documentsSection")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsExternalLinkRow
                  icon="security-lock"
                  title={t("settings.privacy.privacyPolicy")}
                  href={privacyPolicyURL}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsExternalLinkRow
                  icon="left-to-right-list-bullet"
                  title={t("settings.privacy.termsOfUse")}
                  href={termsOfUseURL}
                />
              </div>
            </section>

            <SettingsFootnote icon="information-circle" text={t("settings.privacy.mobileNote")} />
          </div>
        )}

        {destination === "preferences" && (
          <div className="settings-detail-stack">
            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.theme")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsOptionRow
                  icon="laptop"
                  title={t("settings.theme.system")}
                  subtitle={t("settings.theme.systemDesc")}
                  checked={theme === "system"}
                  onSelect={() => onChangeTheme("system")}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsOptionRow
                  icon="sun-01"
                  title={t("settings.theme.light")}
                  subtitle={t("settings.theme.lightDesc")}
                  checked={theme === "light"}
                  onSelect={() => onChangeTheme("light")}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsOptionRow
                  icon="moon-02"
                  title={t("settings.theme.dark")}
                  subtitle={t("settings.theme.darkDesc")}
                  checked={theme === "dark"}
                  onSelect={() => onChangeTheme("dark")}
                />
              </div>
            </section>

            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.language")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsOptionRow
                  icon="globe-02"
                  title="English"
                  subtitle={t("settings.language.enDesc")}
                  checked={locale === "en"}
                  onSelect={() => onChangeLocale("en")}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsOptionRow
                  icon="globe-02"
                  title="Čeština"
                  subtitle={t("settings.language.csDesc")}
                  checked={locale === "cs"}
                  onSelect={() => onChangeLocale("cs")}
                />
              </div>
            </section>

            <SettingsFootnote
              icon="information-circle"
              text={t("settings.preferences.localNote")}
            />
          </div>
        )}

        {destination === "about" && (
          <div className="settings-detail-stack">
            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.support.section")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsExternalLinkRow
                  icon="help-circle"
                  title={t("settings.support.helpCenter")}
                  href={helpCenterURL}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsExternalLinkRow
                  icon="mail-01"
                  title={t("settings.support.contact")}
                  subtitle={DEVELOPER_EMAIL}
                  href={`mailto:${DEVELOPER_EMAIL}`}
                />
                <div className="settings-row-divider settings-row-divider-indented" />
                <SettingsExternalLinkRow
                  icon="github-01"
                  title={t("settings.support.github")}
                  href={GITHUB_REPO_URL}
                />
              </div>
            </section>

            <section className="settings-section-block">
              <h3 className="settings-detail-header">{t("settings.about.section")}</h3>
              <div className="settings-surface settings-surface-flush">
                <SettingsValueRow
                  label={t("settings.about.application")}
                  value={t("app.webSubtitle")}
                />
                <div className="settings-row-divider" />
                <SettingsValueRow
                  label={t("settings.about.ecosystem")}
                  value={t("settings.about.ecosystemValue")}
                />
                <div className="settings-row-divider" />
                <SettingsValueRow
                  label={t("settings.about.accessMode")}
                  value={t("settings.about.accessModeValue")}
                />
              </div>
            </section>
          </div>
        )}
      </div>

      {/* Native Gradey Sign-Out Confirmation Modal */}
      {confirmingLogout && (
        <div
          className="modal-backdrop"
          role="dialog"
          aria-modal="true"
          aria-labelledby="logout-confirm-title"
          onClick={() => {
            if (!isLoggingOut) setConfirmingLogout(false);
          }}
        >
          <div
            className="modal-sheet settings-confirm-sheet"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="settings-confirm-header">
              <div className="settings-confirm-icon" aria-hidden="true">
                <Icon name="logout-01" size={20} color="var(--band-poor)" />
              </div>
              <div>
                <h2 id="logout-confirm-title" className="settings-confirm-title">
                  {t("settings.logoutConfirm.title")}
                </h2>
                <p className="settings-confirm-body">{t("settings.logoutConfirm.body")}</p>
              </div>
            </div>

            <div className="settings-confirm-actions">
              <button
                type="button"
                className="icon-btn"
                disabled={isLoggingOut}
                onClick={() => setConfirmingLogout(false)}
              >
                <span>{t("action.cancel")}</span>
              </button>
              <button
                type="button"
                className="settings-danger-btn"
                disabled={isLoggingOut}
                onClick={onLogout}
                data-testid="logout-confirm-button"
              >
                <Icon
                  name={isLoggingOut ? "refresh-04" : "logout-01"}
                  size={15}
                  className={isLoggingOut ? "spin" : ""}
                />
                <span>{t("action.logout")}</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SettingsIcon({ name, color }: { name: string; color?: string }) {
  return (
    <span className="settings-icon-frame" style={{ color: color ?? "var(--brand-primary)" }}>
      <Icon name={name} size={17} />
    </span>
  );
}

function SettingsOverviewRow({
  icon,
  title,
  subtitle,
  statusDot = false,
  selected,
  onSelect,
}: {
  icon: string;
  title: string;
  subtitle?: string;
  statusDot?: boolean;
  selected: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      className="settings-nav-row"
      data-selected={selected}
      onClick={onSelect}
    >
      <SettingsIcon name={icon} />
      <div className="settings-nav-copy">
        <span className="settings-row-title">{title}</span>
        {subtitle && (
          <span className="settings-nav-subtitle">
            {statusDot && <span className="settings-live-dot" aria-hidden="true" />}
            <span>{subtitle}</span>
          </span>
        )}
      </div>
      <Icon name="arrow-right-01" size={14} className="settings-disclosure" />
    </button>
  );
}

function SettingsValueRow({
  label,
  value,
  tabular = false,
  multiline = false,
}: {
  label: string;
  value: string;
  tabular?: boolean;
  multiline?: boolean;
}) {
  return (
    <div className="settings-value-row" data-multiline={multiline}>
      <span className="settings-value-label">{label}</span>
      <span className={`settings-value-text ${tabular ? "tabular" : ""}`.trim()}>{value}</span>
    </div>
  );
}

function SettingsActionRow({
  icon,
  title,
  subtitle,
  destructive = false,
  accessory = "disclosure",
  disabled = false,
  onClick,
  testId,
}: {
  icon: string;
  title: string;
  subtitle?: string;
  destructive?: boolean;
  accessory?: "disclosure" | "none";
  disabled?: boolean;
  onClick: () => void;
  testId?: string;
}) {
  const tint = destructive ? "var(--band-poor)" : undefined;
  return (
    <button
      type="button"
      className="settings-action-row"
      data-destructive={destructive}
      disabled={disabled}
      onClick={onClick}
      data-testid={testId}
    >
      <SettingsIcon name={icon} color={tint} />
      <div className="settings-nav-copy">
        <span className="settings-row-title" style={tint ? { color: tint } : undefined}>
          {title}
        </span>
        {subtitle && <span className="settings-nav-subtitle">{subtitle}</span>}
      </div>
      {accessory === "disclosure" && (
        <Icon name="arrow-right-01" size={14} className="settings-disclosure" />
      )}
    </button>
  );
}

function SettingsExternalLinkRow({
  icon,
  title,
  subtitle,
  href,
}: {
  icon: string;
  title: string;
  subtitle?: string;
  href: string;
}) {
  const isMail = href.startsWith("mailto:");
  return (
    <a
      className="settings-action-row settings-link-row"
      href={href}
      target={isMail ? undefined : "_blank"}
      rel={isMail ? undefined : "noopener noreferrer"}
    >
      <SettingsIcon name={icon} />
      <div className="settings-nav-copy">
        <span className="settings-row-title">{title}</span>
        {subtitle && <span className="settings-nav-subtitle">{subtitle}</span>}
      </div>
      <Icon
        name={isMail ? "arrow-right-01" : "arrow-up-right-01"}
        size={14}
        className="settings-disclosure"
      />
    </a>
  );
}

function SettingsOptionRow({
  icon,
  title,
  subtitle,
  checked,
  onSelect,
}: {
  icon: string;
  title: string;
  subtitle?: string;
  checked: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      className="settings-option-row"
      role="radio"
      aria-checked={checked}
      data-checked={checked}
      onClick={onSelect}
    >
      <SettingsIcon name={icon} />
      <div className="settings-nav-copy">
        <span className="settings-row-title">{title}</span>
        {subtitle && <span className="settings-nav-subtitle">{subtitle}</span>}
      </div>
      <span className="settings-check-slot" aria-hidden="true">
        {checked && <Icon name="tick-02" size={16} color="var(--brand-primary)" />}
      </span>
    </button>
  );
}

function SettingsFeatureRow({
  icon,
  title,
  description,
}: {
  icon: string;
  title: string;
  description: ReactNode;
}) {
  return (
    <div className="settings-feature-row">
      <SettingsIcon name={icon} />
      <div className="settings-nav-copy">
        <span className="settings-row-title">{title}</span>
        <span className="settings-feature-desc">{description}</span>
      </div>
    </div>
  );
}

function SettingsFootnote({ icon, text }: { icon: string; text: string }) {
  return (
    <div className="settings-footnote">
      <Icon name={icon} size={15} color="var(--text-secondary)" />
      <span>{text}</span>
    </div>
  );
}
