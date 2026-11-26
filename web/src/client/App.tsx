import { useCallback, useEffect, useState } from "react";
import { ApiError, webApi } from "./api.ts";
import { detectDefaultLocale, translate, type WebLocale } from "../shared/i18n.ts";
import { isChristmasSeason, parseStudentDisplayName } from "../shared/schoolMath.ts";
import type { SchoolOverviewResponse, TimetableKind, WebSessionSummary } from "../shared/types.ts";
import { EmptyState, GradeyWordmark, Icon } from "./components/Primitives.tsx";
import { QRLoginScreen, type ThemeMode } from "./views/QRLoginScreen.tsx";
import { TodaySectionView } from "./views/TodaySectionView.tsx";
import { MarksSectionView } from "./views/MarksSectionView.tsx";
import { TimetableSectionView } from "./views/TimetableSectionView.tsx";
import { AbsenceSectionView } from "./views/AbsenceSectionView.tsx";
import { HomeworkSectionView } from "./views/HomeworkSectionView.tsx";
import { SettingsSectionView } from "./views/SettingsSectionView.tsx";

type NavSection = "today" | "marks" | "timetable" | "absence" | "homework" | "settings";

// Non-sensitive UI display preferences only. Authentication tokens are NEVER stored in localStorage.
const LOCALE_PREF_KEY = "gradey.ui.locale";
const THEME_PREF_KEY = "gradey.ui.theme";

export function App() {
  const [locale, setLocaleState] = useState<WebLocale>(() => {
    const saved = localStorage.getItem(LOCALE_PREF_KEY);
    return saved === "cs" || saved === "en" ? saved : detectDefaultLocale();
  });

  const [theme, setThemeState] = useState<ThemeMode>(() => {
    const saved = localStorage.getItem(THEME_PREF_KEY);
    return saved === "light" || saved === "dark" || saved === "system" ? saved : "system";
  });

  const [authPhase, setAuthPhase] = useState<"checking" | "signedOut" | "signedIn">("checking");
  const [session, setSession] = useState<WebSessionSummary | null>(null);
  const [reauthNotice, setReauthNotice] = useState<string | null>(null);

  const [activeNav, setActiveNav] = useState<NavSection>("today");
  const [timetableKind, setTimetableKind] = useState<TimetableKind>("weekly");
  const [focusedSubjectId, setFocusedSubjectId] = useState<string | null>(null);
  const [focusedHomeworkId, setFocusedHomeworkId] = useState<string | null>(null);

  const [overview, setOverview] = useState<SchoolOverviewResponse | null>(null);
  const [isLoadingData, setIsLoadingData] = useState<boolean>(false);
  const [isRefreshing, setIsRefreshing] = useState<boolean>(false);
  const [dataError, setDataError] = useState<string | null>(null);
  const [isOffline, setIsOffline] = useState<boolean>(
    typeof navigator !== "undefined" ? !navigator.onLine : false,
  );
  const [isLoggingOut, setIsLoggingOut] = useState<boolean>(false);

  const t = useCallback(
    (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
      translate(locale, key, params),
    [locale],
  );

  const setLocale = (next: WebLocale) => {
    setLocaleState(next);
    localStorage.setItem(LOCALE_PREF_KEY, next);
    document.documentElement.lang = next;
  };

  const setTheme = (next: ThemeMode) => {
    setThemeState(next);
    localStorage.setItem(THEME_PREF_KEY, next);
  };

  // Apply light/dark + seasonal theme attributes on <html>
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const resolved =
        theme === "system" ? (media.matches ? "dark" : "light") : theme;
      document.documentElement.setAttribute("data-theme", resolved);
      document.documentElement.setAttribute(
        "data-christmas",
        isChristmasSeason() ? "true" : "false",
      );
      document.documentElement.lang = locale;
    };
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme, locale]);

  // Network online/offline tracking
  useEffect(() => {
    const onOnline = () => setIsOffline(false);
    const onOffline = () => setIsOffline(true);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, []);

  const handleForcedSignOut = useCallback(
    (notice?: string) => {
      setSession(null);
      setOverview(null);
      setAuthPhase("signedOut");
      if (notice) setReauthNotice(notice);
    },
    [],
  );

  // Initial session check on page load
  useEffect(() => {
    let cancelled = false;
    webApi
      .checkSession()
      .then((res) => {
        if (cancelled) return;
        if (res.authenticated && res.session) {
          setSession(res.session);
          setAuthPhase("signedIn");
        } else {
          setAuthPhase("signedOut");
        }
      })
      .catch(() => {
        if (!cancelled) setAuthPhase("signedOut");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Load school overview upon authentication
  const loadOverview = useCallback(
    async (isBackgroundRefresh = false) => {
      if (isBackgroundRefresh) {
        setIsRefreshing(true);
      } else {
        setIsLoadingData(true);
      }
      setDataError(null);

      try {
        const res = await webApi.fetchOverview();
        setOverview(res);
      } catch (err) {
        if (err instanceof ApiError && err.status === 401) {
          handleForcedSignOut(
            err.code === "provider_reauth_required"
              ? t("status.reauthRequired")
              : undefined,
          );
          return;
        }
        setDataError(err instanceof Error ? err.message : "Failed to load school data");
      } finally {
        setIsLoadingData(false);
        setIsRefreshing(false);
      }
    },
    [handleForcedSignOut, t],
  );

  useEffect(() => {
    if (authPhase !== "signedIn") return;
    void loadOverview(false);

    // Subscribe to real-time remote revocation from Gradey mobile
    const unsubscribeRevoke = webApi.subscribeSessionRevocation(() => {
      handleForcedSignOut();
    });
    return () => {
      unsubscribeRevoke();
    };
  }, [authPhase, loadOverview, handleForcedSignOut]);

  const handleLogout = async () => {
    setIsLoggingOut(true);
    try {
      await webApi.logout();
    } finally {
      setIsLoggingOut(false);
      handleForcedSignOut();
    }
  };

  if (authPhase === "checking") {
    return (
      <div
        className="aurora-canvas"
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "20px",
        }}
      >
        <GradeyWordmark width={150} height={42} />
        <Icon name="refresh-04" size={22} className="spin" color="var(--brand-primary)" />
      </div>
    );
  }

  if (authPhase === "signedOut" || !session) {
    return (
      <QRLoginScreen
        locale={locale}
        onChangeLocale={setLocale}
        theme={theme}
        onChangeTheme={setTheme}
        reauthNotice={reauthNotice}
        onAuthenticated={(newSession) => {
          setReauthNotice(null);
          setSession(newSession);
          setActiveNav("today");
          setAuthPhase("signedIn");
        }}
      />
    );
  }

  const parsedStudent = parseStudentDisplayName(
    overview?.user?.fullName || session?.studentName,
    overview?.user?.userClass?.abbrev ?? session?.className,
    session.provider,
  );
  const studentDisplayName = parsedStudent.fullName;
  const initials = parsedStudent.initials;

  const navItems: Array<{ id: NavSection; icon: string; label: string }> = [
    { id: "today", icon: "dashboard-square-01", label: t("nav.today") },
    { id: "marks", icon: "analytics-01", label: t("nav.marks") },
    { id: "timetable", icon: "calendar-03", label: t("nav.timetable") },
    { id: "absence", icon: "calendar-remove-02", label: t("nav.absence") },
    { id: "homework", icon: "check-list", label: t("nav.homework") },
    { id: "settings", icon: "settings-01", label: t("nav.settings") },
  ];

  const currentNavTitle = navItems.find((n) => n.id === activeNav)?.label ?? "Gradey";

  return (
    <div className="aurora-canvas app-layout">
      {/* Sidebar */}
      <aside className="app-sidebar">
        <div>
          <div style={{ padding: "4px 10px" }}>
            <GradeyWordmark width={108} height={28} />
          </div>

          <nav className="sidebar-nav" aria-label="Main navigation">
            {navItems.map((item) => (
              <button
                key={item.id}
                type="button"
                className="sidebar-item"
                data-active={activeNav === item.id}
                onClick={() => setActiveNav(item.id)}
              >
                <Icon name={item.icon} size={17} />
                <span>{item.label}</span>
              </button>
            ))}
          </nav>
        </div>

        <button
          type="button"
          className="sidebar-profile"
          data-active={activeNav === "settings"}
          onClick={() => setActiveNav("settings")}
        >
          <div className="avatar-circle">{initials || "G"}</div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div
              style={{
                fontSize: "13.5px",
                fontWeight: 600,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {studentDisplayName}
            </div>
            <div
              style={{
                fontSize: "11.5px",
                color: "var(--text-secondary)",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {overview?.user?.userClass?.abbrev ??
                session.className ??
                session.schoolName ??
                ""}
            </div>
          </div>
        </button>
      </aside>

      {/* Main Content */}
      <div className="app-main">
        {isOffline && (
          <div className="status-banner" role="status">
            <Icon name="wifi-disconnected-01" size={16} color="var(--accent-orange)" />
            <span>{t("status.offline")}</span>
          </div>
        )}

        <header className="app-header">
          <h1 className="app-header-title">{currentNavTitle}</h1>

          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            {activeNav === "timetable" && (
              <div className="segmented-control">
                <button
                  type="button"
                  className="segmented-btn"
                  data-active={timetableKind === "weekly"}
                  onClick={() => setTimetableKind("weekly")}
                >
                  {t("timetable.weekly")}
                </button>
                <button
                  type="button"
                  className="segmented-btn"
                  data-active={timetableKind === "permanent"}
                  onClick={() => setTimetableKind("permanent")}
                >
                  {t("timetable.permanent")}
                </button>
              </div>
            )}

            <button
              type="button"
              className="icon-btn"
              disabled={isLoadingData || isRefreshing}
              onClick={() => void loadOverview(true)}
            >
              <Icon
                name="refresh-04"
                size={15}
                className={isLoadingData || isRefreshing ? "spin" : ""}
              />
              <span>{isRefreshing ? t("status.refreshing") : t("action.refresh")}</span>
            </button>
          </div>
        </header>

        {activeNav === "settings" ? (
          <SettingsSectionView
            user={overview?.user ?? null}
            session={session}
            locale={locale}
            onChangeLocale={setLocale}
            theme={theme}
            onChangeTheme={setTheme}
            onLogout={() => void handleLogout()}
            isLoggingOut={isLoggingOut}
          />
        ) : isLoadingData && !overview ? (
          <div className="page-scroll">
            <EmptyState icon="refresh-04" title={t("status.loading")} />
          </div>
        ) : dataError && !overview ? (
          <div className="page-scroll">
            <EmptyState
              icon="alert-02"
              title={dataError}
              actionLabel={t("action.retry")}
              onAction={() => void loadOverview(false)}
            />
          </div>
        ) : overview ? (
          <>
            {activeNav === "today" && (
              <TodaySectionView
                overview={overview}
                session={session}
                locale={locale}
                onNavigateMarks={(subjectId) => {
                  if (subjectId) setFocusedSubjectId(subjectId);
                  setActiveNav("marks");
                }}
                onNavigateTimetable={() => setActiveNav("timetable")}
                onNavigateHomework={(hwId) => {
                  if (hwId) setFocusedHomeworkId(hwId);
                  setActiveNav("homework");
                }}
              />
            )}

            {activeNav === "marks" && (
              <MarksSectionView
                marks={overview.marks}
                locale={locale}
                initialSubjectId={focusedSubjectId}
              />
            )}

            {activeNav === "timetable" && (
              <TimetableSectionView
                initialWeek={overview.timetable}
                locale={locale}
                kind={timetableKind}
                onChangeKind={setTimetableKind}
              />
            )}

            {activeNav === "absence" && (
              <AbsenceSectionView absences={overview.absences} locale={locale} />
            )}

            {activeNav === "homework" && (
              <HomeworkSectionView
                homeworks={overview.homeworks}
                locale={locale}
                initialHomeworkId={focusedHomeworkId}
              />
            )}
          </>
        ) : null}
      </div>
    </div>
  );
}
