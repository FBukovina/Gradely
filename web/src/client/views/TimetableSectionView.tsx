import { useEffect, useState } from "react";
import { mondayOfWeek, shiftIsoDays } from "../../shared/schoolMath.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type {
  ScheduledDay,
  ScheduledLesson,
  TimetableKind,
  TimetableWeek,
} from "../../shared/types.ts";
import { webApi } from "../api.ts";
import {
  EmptyState,
  formatShortDate,
  Icon,
  StatusChip,
} from "../components/Primitives.tsx";

interface TimetableSectionViewProps {
  initialWeek: TimetableWeek | null;
  locale: WebLocale;
}

const WEEKDAY_NAMES: Record<WebLocale, string[]> = {
  en: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
  cs: ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"],
};

export function TimetableSectionView({
  initialWeek,
  locale,
}: TimetableSectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const [kind, setKind] = useState<TimetableKind>("weekly");
  const [weekStart, setWeekStart] = useState<string>(
    initialWeek?.weekStart ?? mondayOfWeek(new Date()),
  );
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
  const rangeLabel = `${formatShortDate(weekStart, locale)} – ${formatShortDate(weekEnd, locale)}`;

  return (
    <div className="page-scroll-wide">
      {/* Week Nav & Kind Switch */}
      <div className="timetable-toolbar">
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          {kind === "weekly" ? (
            <>
              <button
                type="button"
                className="icon-btn"
                onClick={() => setWeekStart(shiftIsoDays(weekStart, -7))}
                aria-label={t("action.previousWeek")}
              >
                <Icon name="arrow-left-01" size={16} />
              </button>
              <span
                className="tabular"
                style={{ fontSize: "15px", fontWeight: 700, minWidth: "130px", textAlign: "center" }}
              >
                {rangeLabel}
              </span>
              <button
                type="button"
                className="icon-btn"
                onClick={() => setWeekStart(shiftIsoDays(weekStart, 7))}
                aria-label={t("action.nextWeek")}
              >
                <Icon name="arrow-right-01" size={16} />
              </button>
              <button
                type="button"
                className="icon-btn"
                onClick={() => setWeekStart(mondayOfWeek(new Date()))}
              >
                {t("action.today")}
              </button>
            </>
          ) : (
            <div style={{ fontSize: "13.5px", color: "var(--text-secondary)" }}>
              {t("timetable.permanentHint")}
            </div>
          )}
          {isLoading && <Icon name="refresh-04" size={15} className="spin" />}
        </div>

        <div className="segmented-control">
          <button
            type="button"
            className="segmented-btn"
            data-active={kind === "weekly"}
            onClick={() => setKind("weekly")}
          >
            {t("timetable.weekly")}
          </button>
          <button
            type="button"
            className="segmented-btn"
            data-active={kind === "permanent"}
            onClick={() => setKind("permanent")}
          >
            {t("timetable.permanent")}
          </button>
        </div>
      </div>

      {error ? (
        <EmptyState icon="alert-02" title={error} />
      ) : !weekData || weekData.days.length === 0 || weekData.hours.length === 0 ? (
        <EmptyState
          icon="calendar-03"
          title={t("timetable.empty.title")}
          description={t("timetable.empty.body")}
        />
      ) : (
        <div className="timetable-grid-wrap">
          <table className="timetable-table">
            <thead>
              <tr>
                <th className="timetable-day-cell" />
                {weekData.hours.map((hour) => (
                  <th
                    key={hour.id}
                    style={{ textAlign: "center", padding: "8px 4px", fontWeight: 600 }}
                  >
                    <div style={{ fontSize: "13px" }}>{hour.caption}</div>
                    <div
                      className="tabular"
                      style={{ fontSize: "11px", color: "var(--text-secondary)", fontWeight: 400 }}
                    >
                      {hour.beginTime}–{hour.endTime}
                    </div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {weekData.days.map((day) => {
                const dayName =
                  WEEKDAY_NAMES[locale][Math.max(0, (day.dayOfWeek || 1) - 1)] ?? "";
                const isHoliday = day.dayType !== "workDay" && day.lessons.length === 0;

                return (
                  <tr
                    key={day.id}
                    style={{
                      background: day.isToday ? "rgba(23, 161, 133, 0.035)" : undefined,
                    }}
                  >
                    <td className="timetable-day-cell">
                      <div
                        style={{
                          fontSize: "14px",
                          fontWeight: 700,
                          color: day.isToday ? "var(--brand-primary)" : "var(--text-primary)",
                        }}
                      >
                        {dayName}
                      </div>
                      {day.date && (
                        <div
                          className="tabular"
                          style={{ fontSize: "12px", color: "var(--text-secondary)" }}
                        >
                          {formatShortDate(day.date, locale)}
                        </div>
                      )}
                    </td>

                    {isHoliday ? (
                      <td
                        colSpan={weekData.hours.length}
                        style={{
                          verticalAlign: "middle",
                          padding: "16px",
                          color: "var(--text-secondary)",
                          fontSize: "13.5px",
                        }}
                      >
                        {day.dayDescription || t("timetable.dayOff")}
                      </td>
                    ) : (
                      weekData.hours.map((hour) => {
                        const cellLessons = day.lessons.filter((l) => l.hour.id === hour.id);
                        return (
                          <td key={hour.id}>
                            <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
                              {cellLessons.map((lesson) => (
                                <button
                                  key={lesson.id}
                                  type="button"
                                  className="lesson-tile"
                                  data-change={lesson.changeKind}
                                  onClick={() => setSelectedLesson({ lesson, day })}
                                >
                                  <div
                                    style={{
                                      display: "flex",
                                      alignItems: "center",
                                      justifyContent: "space-between",
                                      gap: "4px",
                                    }}
                                  >
                                    <span
                                      style={{
                                        fontSize: "14px",
                                        fontWeight: 700,
                                        textDecoration:
                                          lesson.changeKind === "canceled"
                                            ? "line-through"
                                            : "none",
                                      }}
                                    >
                                      {lesson.subjectAbbrev ||
                                        lesson.subjectName ||
                                        lesson.change?.changeSubject ||
                                        "—"}
                                    </span>
                                    {lesson.hasHomework && (
                                      <span
                                        style={{
                                          width: "6px",
                                          height: "6px",
                                          borderRadius: "50%",
                                          background: "var(--brand-primary)",
                                        }}
                                      />
                                    )}
                                  </div>

                                  <div
                                    style={{
                                      display: "flex",
                                      justifyContent: "space-between",
                                      fontSize: "11px",
                                      color: "var(--text-secondary)",
                                      gap: "4px",
                                    }}
                                  >
                                    <span
                                      style={{
                                        overflow: "hidden",
                                        textOverflow: "ellipsis",
                                        whiteSpace: "nowrap",
                                      }}
                                    >
                                      {lesson.roomAbbrev || ""}
                                    </span>
                                    <span
                                      style={{
                                        overflow: "hidden",
                                        textOverflow: "ellipsis",
                                        whiteSpace: "nowrap",
                                      }}
                                    >
                                      {lesson.teacherAbbrev || ""}
                                    </span>
                                  </div>
                                </button>
                              ))}
                            </div>
                          </td>
                        );
                      })
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
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
                    caption: selectedLesson.lesson.hour.caption,
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
                />
              </div>
            )}

            <div className="plain-rows">
              {selectedLesson.lesson.teacherName && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)", fontSize: "14px" }}>
                    {t("timetable.detail.teacher")}
                  </span>
                  <span style={{ fontWeight: 600, fontSize: "14px" }}>
                    {selectedLesson.lesson.teacherName}
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
                <div className="plain-row" style={{ flexDirection: "column", alignItems: "flex-start", gap: "4px" }}>
                  <span style={{ color: "var(--text-secondary)", fontSize: "13px" }}>
                    {t("timetable.detail.theme")}
                  </span>
                  <span style={{ fontSize: "14px" }}>{selectedLesson.lesson.theme}</span>
                </div>
              )}
              {selectedLesson.lesson.change?.description && (
                <div className="plain-row" style={{ flexDirection: "column", alignItems: "flex-start", gap: "4px" }}>
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
