import { type CSSProperties, useEffect, useMemo, useState } from "react";
import {
  formatTeacherCardName,
  mondayOfWeek,
  pragueMinutesNow,
  shiftIsoDays,
  visibleTimetableHours,
} from "../../shared/schoolMath.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type {
  LessonChangeKind,
  ScheduledDay,
  ScheduledLesson,
  TimetableHour,
  TimetableKind,
  TimetableWeek,
} from "../../shared/types.ts";
import { webApi } from "../api.ts";
import { EmptyState, Icon, StatusChip } from "../components/Primitives.tsx";

interface TimetableSectionViewProps {
  initialWeek: TimetableWeek | null;
  locale: WebLocale;
  kind?: TimetableKind;
  onChangeKind?: (kind: TimetableKind) => void;
}

const WEEKDAY_NAMES: Record<WebLocale, string[]> = {
  en: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"],
  cs: ["PO", "ÚT", "ST", "ČT", "PÁ", "SO", "NE"],
};

function formatCzechWeekRange(mondayIso: string, fridayIso: string): string {
  const fmt = (iso: string) => {
    const [, m, d] = iso.slice(0, 10).split("-").map(Number);
    if (!m || !d) return iso.slice(0, 10);
    return `${d}. ${m}.`;
  };
  return `${fmt(mondayIso)} – ${fmt(fridayIso)}`;
}

function dayNumberFromIso(iso: string | null): string {
  if (!iso) return "";
  const d = Number(iso.slice(8, 10));
  return Number.isFinite(d) && d > 0 ? String(d) : "";
}

function stripLeadingZeroTime(hhmm: string): string {
  return hhmm.trim().replace(/^0(\d:)/, "$1");
}

function parseClockMinutes(hhmm: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

function isHourRunningNow(hour: TimetableHour, nowMinutes: number): boolean {
  const start = parseClockMinutes(hour.beginTime);
  const end = parseClockMinutes(hour.endTime);
  if (start == null || end == null) return false;
  return nowMinutes >= start && nowMinutes < end;
}

function changeAccentColor(kind: LessonChangeKind): string {
  switch (kind) {
    case "substitution":
      return "#F59E0B";
    case "roomChanged":
      return "#22B8CF";
    case "canceled":
      return "var(--band-poor)";
    case "added":
      return "#A855F7";
    default:
      return "var(--brand-primary)";
  }
}

export function TimetableSectionView({
  initialWeek,
  locale,
  kind: controlledKind,
  onChangeKind,
}: TimetableSectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const [internalKind, setInternalKind] = useState<TimetableKind>("weekly");
  const kind = controlledKind ?? internalKind;
  const setKind = onChangeKind ?? setInternalKind;

  const currentMonday = mondayOfWeek(new Date());
  const [weekStart, setWeekStart] = useState<string>(initialWeek?.weekStart ?? currentMonday);
  const [weekData, setWeekData] = useState<TimetableWeek | null>(initialWeek);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedLesson, setSelectedLesson] = useState<{
    lesson: ScheduledLesson;
    day: ScheduledDay;
  } | null>(null);

  useEffect(() => {
    if (
      kind === "weekly" &&
      initialWeek &&
      initialWeek.weekStart === weekStart &&
      initialWeek.kind === "weekly"
    ) {
      setWeekData(initialWeek);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setError(null);
    webApi
      .fetchTimetable(weekStart, kind)
      .then((res) => {
        if (!cancelled) setWeekData(res);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Error");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [weekStart, kind, initialWeek]);

  const weekEnd = shiftIsoDays(weekStart, 4);
  const rangeLabel = formatCzechWeekRange(weekStart, weekEnd);
  const isViewingCurrentWeek = weekStart === currentMonday;
  const displayedHours = useMemo(() => visibleTimetableHours(weekData), [weekData]);
  const nowMinutes = pragueMinutesNow(new Date());

  return (
    <div className="week-grid-page">
      {/* Top Week Navigation Bar (1:1 with GradelyMac WeekNavBar) */}
      {kind === "weekly" ? (
        <div className="week-nav-bar">
          <button
            type="button"
            className="week-nav-arrow"
            onClick={() => setWeekStart(shiftIsoDays(weekStart, -7))}
            aria-label={t("action.previousWeek")}
          >
            <Icon name="arrow-left-01" size={18} />
          </button>

          <div className="week-nav-center">
            <div className="week-nav-title tabular">
              <span>{rangeLabel}</span>
              {isLoading && <Icon name="refresh-04" size={14} className="spin" />}
            </div>
            {!isViewingCurrentWeek && (
              <button
                type="button"
                className="week-nav-today"
                onClick={() => setWeekStart(currentMonday)}
              >
                {t("action.today")}
              </button>
            )}
          </div>

          <button
            type="button"
            className="week-nav-arrow"
            onClick={() => setWeekStart(shiftIsoDays(weekStart, 7))}
            aria-label={t("action.nextWeek")}
          >
            <Icon name="arrow-right-01" size={18} />
          </button>
        </div>
      ) : (
        <div className="week-permanent-banner">
          <Icon name="calendar-03" size={16} color="var(--brand-primary)" />
          <div>
            <div style={{ fontSize: "14px", fontWeight: 600 }}>{t("timetable.permanent")}</div>
            <div style={{ fontSize: "12.5px", color: "var(--text-secondary)" }}>
              {t("timetable.permanentHint")}
            </div>
          </div>
          {!controlledKind && (
            <button
              type="button"
              className="icon-btn"
              style={{ marginLeft: "auto" }}
              onClick={() => setKind("weekly")}
            >
              {t("timetable.weekly")}
            </button>
          )}
        </div>
      )}

      {error ? (
        <EmptyState icon="alert-02" title={error} />
      ) : !weekData || weekData.days.length === 0 || displayedHours.length === 0 ? (
        <EmptyState
          icon="calendar-03"
          title={t("timetable.empty.title")}
          description={t("timetable.empty.body")}
        />
      ) : (
        <div className="week-grid-scroll">
          <div
            className="week-grid"
            style={{ "--day-count": weekData.days.length } as CSSProperties}
          >
            {/* Day Column Headers */}
            <div className="week-grid-header-row">
              <div className="week-grid-corner" />
              {weekData.days.map((day) => {
                const weekday =
                  WEEKDAY_NAMES[locale][Math.max(0, (day.dayOfWeek || 1) - 1)] ?? "";
                const dayNum = dayNumberFromIso(day.date);
                const isHoliday = day.dayType !== "workDay" && day.lessons.length === 0;

                return (
                  <div key={day.id} className="week-day-header" data-today={day.isToday}>
                    <div className="week-day-header-line">
                      <span className="week-day-abbrev">{weekday}</span>
                      {dayNum && <span className="week-day-number tabular">{dayNum}</span>}
                    </div>
                    {isHoliday && (
                      <div className="week-day-off">
                        {day.dayDescription || t("timetable.dayOff")}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Period Rows (1 .. last scheduled hour, e.g. 8) */}
            {displayedHours.map((hour) => {
              const periodNum = hour.caption.trim().replace(/\.$/, "");
              const isHourActiveToday =
                weekData.days.some(
                  (d) =>
                    d.isToday &&
                    d.lessons.some((l) => l.hour.id === hour.id && l.changeKind !== "canceled"),
                ) && isHourRunningNow(hour, nowMinutes);

              return (
                <div key={hour.id} className="week-period-row">
                  {/* Left Period & Time Gutter */}
                  <div className="week-hour-gutter" data-now={isHourActiveToday}>
                    <div className="week-hour-number tabular">{periodNum}</div>
                    {hour.beginTime && (
                      <>
                        <div className="week-hour-begin tabular">
                          {stripLeadingZeroTime(hour.beginTime)}
                        </div>
                        <div className="week-hour-end tabular">
                          {stripLeadingZeroTime(hour.endTime)}
                        </div>
                      </>
                    )}
                  </div>

                  {/* Day Columns for This Period */}
                  {weekData.days.map((day) => {
                    const cellLessons = day.lessons.filter((l) => l.hour.id === hour.id);
                    const isLessonNow =
                      day.isToday && isHourRunningNow(hour, nowMinutes);

                    return (
                      <div key={day.id} className="week-cell">
                        {cellLessons.map((lesson) => {
                          const isCanceled = lesson.changeKind === "canceled";
                          const accent = changeAccentColor(lesson.changeKind);
                          const subjectTitle =
                            lesson.subjectName ||
                            lesson.subjectAbbrev ||
                            lesson.change?.changeSubject ||
                            "—";
                          const roomPart = lesson.roomAbbrev || lesson.roomName || "";
                          const teacherPart = formatTeacherCardName(
                            lesson.teacherName,
                            lesson.teacherAbbrev,
                          );
                          const groupPart =
                            lesson.groups.length > 0 ? lesson.groups.join(", ") : "";
                          const detailLine = isCanceled
                            ? ""
                            : [roomPart, teacherPart, groupPart].filter(Boolean).join(" · ");
                          const changeLabel =
                            lesson.changeKind !== "none"
                              ? t(`timetable.change.${lesson.changeKind}`)
                              : null;

                          return (
                            <button
                              key={lesson.id}
                              type="button"
                              className="week-lesson-item"
                              data-canceled={isCanceled}
                              data-now={!isCanceled && isLessonNow}
                              onClick={() => setSelectedLesson({ lesson, day })}
                            >
                              <span
                                className="week-lesson-bar"
                                style={{
                                  backgroundColor: accent,
                                  opacity: isCanceled ? 0.45 : 1,
                                }}
                                aria-hidden="true"
                              />
                              <span className="week-lesson-body">
                                <span className="week-lesson-title-row">
                                  <span className="week-lesson-subject">{subjectTitle}</span>
                                  {lesson.hasHomework && (
                                    <span className="lesson-homework-dot" />
                                  )}
                                </span>

                                {detailLine && (
                                  <span className="week-lesson-detail">{detailLine}</span>
                                )}

                                {changeLabel && (
                                  <span
                                    className="week-lesson-change"
                                    style={{ color: accent }}
                                  >
                                    {changeLabel}
                                  </span>
                                )}
                              </span>
                            </button>
                          );
                        })}
                      </div>
                    );
                  })}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Lesson Inspector Modal */}
      {selectedLesson && (
        <div
          className="modal-backdrop"
          onClick={() => setSelectedLesson(null)}
          role="dialog"
          aria-modal="true"
        >
          <div className="modal-sheet" onClick={(e) => e.stopPropagation()}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "flex-start",
                gap: "12px",
                marginBottom: "16px",
              }}
            >
              <div>
                <div style={{ fontSize: "12.5px", color: "var(--text-secondary)" }}>
                  {t("timetable.detail.period", {
                    caption: selectedLesson.lesson.hour.caption.replace(/\.$/, ""),
                  })}{" "}
                  · {selectedLesson.lesson.hour.beginTime}–{selectedLesson.lesson.hour.endTime}
                </div>
                <h3 style={{ fontSize: "21px", fontWeight: 700, margin: "4px 0 0" }}>
                  {selectedLesson.lesson.subjectName ||
                    selectedLesson.lesson.subjectAbbrev ||
                    selectedLesson.lesson.change?.changeSubject ||
                    "—"}
                </h3>
              </div>

              <button
                type="button"
                className="icon-btn"
                onClick={() => setSelectedLesson(null)}
                aria-label={t("action.close")}
              >
                <Icon name="cancel-01" size={15} />
              </button>
            </div>

            {selectedLesson.lesson.changeKind !== "none" && (
              <div style={{ marginBottom: "14px" }}>
                <StatusChip
                  text={t(`timetable.change.${selectedLesson.lesson.changeKind}`)}
                  color={changeAccentColor(selectedLesson.lesson.changeKind)}
                />
              </div>
            )}

            <div className="plain-rows">
              {(selectedLesson.lesson.teacherName || selectedLesson.lesson.teacherAbbrev) && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)", fontSize: "14px" }}>
                    {t("timetable.detail.teacher")}
                  </span>
                  <span style={{ fontWeight: 600, fontSize: "14px" }}>
                    {selectedLesson.lesson.teacherName || selectedLesson.lesson.teacherAbbrev}
                  </span>
                </div>
              )}
              {(selectedLesson.lesson.roomName || selectedLesson.lesson.roomAbbrev) && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)", fontSize: "14px" }}>
                    {t("timetable.detail.room")}
                  </span>
                  <span style={{ fontWeight: 600, fontSize: "14px" }}>
                    {selectedLesson.lesson.roomName || selectedLesson.lesson.roomAbbrev}
                  </span>
                </div>
              )}
              {selectedLesson.lesson.groups.length > 0 && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)", fontSize: "14px" }}>
                    {t("timetable.detail.group")}
                  </span>
                  <span style={{ fontWeight: 600, fontSize: "14px" }}>
                    {selectedLesson.lesson.groups.join(", ")}
                  </span>
                </div>
              )}
              {selectedLesson.lesson.theme && (
                <div
                  className="plain-row"
                  style={{ flexDirection: "column", alignItems: "flex-start", gap: "4px" }}
                >
                  <span style={{ color: "var(--text-secondary)", fontSize: "13px" }}>
                    {t("timetable.detail.theme")}
                  </span>
                  <span style={{ fontSize: "14px" }}>{selectedLesson.lesson.theme}</span>
                </div>
              )}
              {selectedLesson.lesson.change?.description && (
                <div
                  className="plain-row"
                  style={{ flexDirection: "column", alignItems: "flex-start", gap: "4px" }}
                >
                  <span style={{ color: "var(--text-secondary)", fontSize: "13px" }}>
                    {t("timetable.detail.change")}
                  </span>
                  <span style={{ fontSize: "14px" }}>
                    {selectedLesson.lesson.change.description}
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
