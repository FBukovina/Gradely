import { useMemo } from "react";
import {
  formatAverage,
  gradeBandForAverage,
  gradeBandForMark,
  overallStudyAverage,
  parseStudentDisplayName,
  resolveTodayLessonState,
} from "../../shared/schoolMath.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type {
  HomeworkItem,
  MarkItem,
  ScheduledLesson,
  SchoolOverviewResponse,
  WebSessionSummary,
} from "../../shared/types.ts";
import {
  formatShortDate,
  GradeBadge,
  Icon,
  PlainSection,
  StatusChip,
} from "../components/Primitives.tsx";

interface TodaySectionViewProps {
  overview: SchoolOverviewResponse;
  session: WebSessionSummary;
  locale: WebLocale;
  onNavigateMarks: (subjectId?: string) => void;
  onNavigateTimetable: () => void;
  onNavigateHomework: (homeworkId?: string) => void;
}

export function TodaySectionView({
  overview,
  session,
  locale,
  onNavigateMarks,
  onNavigateTimetable,
  onNavigateHomework,
}: TodaySectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const now = new Date();
  const studyAvg = useMemo(
    () => overallStudyAverage(overview.marks.subjects),
    [overview.marks.subjects],
  );
  const lessonState = useMemo(
    () => resolveTodayLessonState(overview.timetable, now),
    [overview.timetable],
  );

  const recentMarks = useMemo(() => {
    const items: Array<{ mark: MarkItem; subjectName: string; subjectAbbrev: string }> = [];
    for (const subj of overview.marks.subjects) {
      for (const mark of subj.marks) {
        items.push({
          mark,
          subjectName: subj.subjectInfo.name,
          subjectAbbrev: subj.subjectInfo.abbrev,
        });
      }
    }
    return items
      .sort((a, b) => (b.mark.markDate || "").localeCompare(a.mark.markDate || ""))
      .slice(0, 5);
  }, [overview.marks.subjects]);

  const openHomework = useMemo(() => {
    return overview.homeworks.homeworks
      .filter((hw) => !hw.isDone && !hw.isClosed)
      .sort((a, b) => (a.dueOn ?? "9999").localeCompare(b.dueOn ?? "9999"))
      .slice(0, 4);
  }, [overview.homeworks.homeworks]);

  const greeting = useMemo(() => {
    const hour = now.getHours();
    if (hour >= 5 && hour < 12) return t("today.greeting.morning");
    if (hour >= 12 && hour < 18) return t("today.greeting.afternoon");
    return t("today.greeting.evening");
  }, [locale]);

  const firstName = parseStudentDisplayName(
    overview.user?.fullName ?? session.studentName,
    overview.user?.userClass?.abbrev ?? session.className,
    session.provider,
  ).firstName;

  return (
    <div className="page-scroll">
      {/* Hero Summary */}
      <div
        style={{
          display: "flex",
          alignItems: "flex-end",
          justifyContent: "space-between",
          gap: "24px",
          flexWrap: "wrap",
          marginBottom: "28px",
        }}
      >
        <div>
          <div style={{ fontSize: "13.5px", fontWeight: 600, color: "var(--text-secondary)" }}>
            {[
              overview.user?.userClass?.abbrev,
              overview.user?.schoolName,
            ]
              .filter(Boolean)
              .join(" · ") || t("app.webSubtitle")}
          </div>
          <h1
            style={{
              fontSize: "34px",
              fontWeight: 700,
              letterSpacing: "-0.02em",
              margin: "4px 0 0",
            }}
          >
            {firstName ? `${greeting}, ${firstName}` : greeting}
          </h1>
        </div>

        {studyAvg != null && (
          <div style={{ textAlign: "right" }}>
            <div className="hero-stat-label">{t("today.studyAverage")}</div>
            <div
              className="tabular"
              style={{
                fontSize: "38px",
                fontWeight: 700,
                lineHeight: 1.05,
                color: `var(--band-${gradeBandForAverage(studyAvg)})`,
              }}
            >
              {formatAverage(studyAvg, locale)}
            </div>
          </div>
        )}
      </div>

      {/* Now and Next */}
      <PlainSection
        title={t("today.nowAndNext")}
        actionLabel={t("today.openTimetable")}
        onAction={onNavigateTimetable}
      >
        {lessonState.todayDay && lessonState.todayDay.lessons.length > 0 && (
          <div style={{ padding: "8px 0 12px", borderBottom: "1px solid var(--hairline)" }}>
            <div className="today-strip">
              {lessonState.todayDay.lessons.map((lesson) => {
                const isCurrent = lessonState.currentLesson?.id === lesson.id;
                const title = lesson.subjectAbbrev || lesson.subjectName || lesson.hour.caption;
                return (
                  <div key={lesson.id} className="today-pill" data-current={isCurrent}>
                    <div
                      className="tabular"
                      style={{ fontSize: "11px", color: "var(--text-secondary)" }}
                    >
                      {lesson.hour.beginTime}
                    </div>
                    <div
                      style={{
                        fontSize: "14px",
                        fontWeight: 700,
                        textDecoration: lesson.changeKind === "canceled" ? "line-through" : "none",
                      }}
                    >
                      {title}
                    </div>
                    <div style={{ fontSize: "11.5px", color: "var(--text-secondary)" }}>
                      {lesson.roomAbbrev || "\u00A0"}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {lessonState.currentLesson && (
          <TodayLessonRow
            lesson={lessonState.currentLesson}
            badge={
              lessonState.minutesRemainingInCurrent != null
                ? t("today.currentLesson", { minutes: lessonState.minutesRemainingInCurrent })
                : t("nav.today")
            }
            highlight
          />
        )}

        {lessonState.nextLesson && (
          <TodayLessonRow
            lesson={lessonState.nextLesson}
            badge={
              !lessonState.currentLesson && lessonState.minutesUntilNext != null
                ? t("today.nextLessonIn", { minutes: lessonState.minutesUntilNext })
                : t("today.nextLesson")
            }
          />
        )}

        {!lessonState.currentLesson && !lessonState.nextLesson && (
          <div className="plain-row" style={{ color: "var(--text-secondary)" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <Icon
                name={
                  lessonState.todayDay && lessonState.todayDay.lessons.length > 0
                    ? "checkmark-circle-02"
                    : "sun-01"
                }
                size={18}
                color="var(--brand-primary)"
              />
              <span style={{ fontWeight: 500 }}>
                {lessonState.todayDay && lessonState.todayDay.lessons.length > 0
                  ? t("today.noMoreLessons")
                  : t("today.noLessonsToday")}
              </span>
            </div>
          </div>
        )}

        {lessonState.changedLessons.map((changed) => (
          <div key={`chg-${changed.id}`} className="plain-row">
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <Icon name="alert-02" size={16} color="var(--accent-orange)" />
              <div>
                <div style={{ fontSize: "14px", fontWeight: 600 }}>
                  {changed.subjectName ||
                    changed.subjectAbbrev ||
                    changed.change?.changeSubject ||
                    t("today.scheduleChanges")}
                </div>
                <div style={{ fontSize: "12.5px", color: "var(--text-secondary)" }}>
                  {[
                    `${changed.hour.caption}. (${changed.hour.beginTime}–${changed.hour.endTime})`,
                    changed.change?.description,
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
              </div>
            </div>
          </div>
        ))}
      </PlainSection>

      {/* Recent Marks */}
      <PlainSection
        title={t("today.recentGrades")}
        actionLabel={t("today.openMarks")}
        onAction={() => onNavigateMarks()}
      >
        {recentMarks.length === 0 ? (
          <div className="plain-row" style={{ color: "var(--text-secondary)" }}>
            <span>{t("today.noRecentGrades")}</span>
          </div>
        ) : (
          recentMarks.map(({ mark, subjectName }) => (
            <button
              key={mark.id}
              type="button"
              className="plain-row-interactive"
              onClick={() => onNavigateMarks(mark.subjectID)}
            >
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: "15px", fontWeight: 600 }}>
                  {mark.caption || mark.theme || t("marks.detail.untitled")}
                </div>
                <div style={{ fontSize: "13px", color: "var(--text-secondary)", marginTop: "2px" }}>
                  {[subjectName, formatShortDate(mark.markDate, locale)].filter(Boolean).join(" · ")}
                </div>
              </div>
              <GradeBadge
                text={
                  mark.isPoints && mark.maxPoints != null
                    ? `${mark.markText}/${mark.maxPoints}`
                    : mark.markText
                }
                band={gradeBandForMark(mark)}
                size="sm"
              />
            </button>
          ))
        )}
      </PlainSection>

      {/* Open Homework */}
      <PlainSection
        title={t("today.upcomingHomework")}
        actionLabel={t("today.openHomework")}
        onAction={() => onNavigateHomework()}
      >
        {openHomework.length === 0 ? (
          <div className="plain-row" style={{ color: "var(--text-secondary)" }}>
            <span>{t("today.noOpenHomework")}</span>
          </div>
        ) : (
          openHomework.map((hw: HomeworkItem) => (
            <button
              key={hw.id}
              type="button"
              className="plain-row-interactive"
              onClick={() => onNavigateHomework(hw.id)}
            >
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: "15px", fontWeight: 600 }}>{hw.title}</div>
                <div style={{ fontSize: "13px", color: "var(--text-secondary)", marginTop: "2px" }}>
                  {[hw.subjectName || hw.subjectAbbrev, hw.teacherName]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
              </div>
              {hw.dueOn && (
                <StatusChip text={t("homework.dueDate", { date: formatShortDate(hw.dueOn, locale) })} />
              )}
            </button>
          ))
        )}
      </PlainSection>
    </div>
  );
}

function TodayLessonRow({
  lesson,
  badge,
  highlight = false,
}: {
  lesson: ScheduledLesson;
  badge: string;
  highlight?: boolean;
}) {
  return (
    <div className="plain-row">
      <div>
        <div
          style={{
            fontSize: "12px",
            fontWeight: 700,
            color: highlight ? "var(--brand-primary)" : "var(--text-secondary)",
            marginBottom: "2px",
          }}
        >
          {badge}
        </div>
        <div style={{ fontSize: "16px", fontWeight: 700 }}>
          {lesson.subjectName || lesson.subjectAbbrev || `${lesson.hour.caption}.`}
        </div>
        <div style={{ fontSize: "13px", color: "var(--text-secondary)", marginTop: "1px" }}>
          {[
            `${lesson.hour.beginTime}–${lesson.hour.endTime}`,
            lesson.roomAbbrev || lesson.roomName,
            lesson.teacherName || lesson.teacherAbbrev,
          ]
            .filter(Boolean)
            .join(" · ")}
        </div>
      </div>
    </div>
  );
}
