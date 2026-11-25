import { useMemo, useState } from "react";
import {
  buildSubjectAbsenceRisks,
  normalizeAbsenceThreshold,
  sumAbsenceDays,
} from "../../shared/schoolMath.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type { AbsenceSnapshot } from "../../shared/types.ts";
import {
  EmptyState,
  formatShortDate,
  RiskCapsuleBar,
  StatusChip,
} from "../components/Primitives.tsx";

type AbsenceSegment = "subjects" | "days" | "months";

interface AbsenceSectionViewProps {
  absences: AbsenceSnapshot;
  locale: WebLocale;
}

export function AbsenceSectionView({ absences, locale }: AbsenceSectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const [segment, setSegment] = useState<AbsenceSegment>("subjects");

  const totals = useMemo(() => sumAbsenceDays(absences.absences), [absences.absences]);
  const threshold = useMemo(
    () => normalizeAbsenceThreshold(absences.percentageThreshold),
    [absences.percentageThreshold],
  );
  const subjectRisks = useMemo(() => buildSubjectAbsenceRisks(absences), [absences]);

  const monthRows = useMemo(() => {
    const map = new Map<string, typeof absences.absences>();
    for (const day of absences.absences) {
      const monthKey = day.date.slice(0, 7);
      if (!monthKey) continue;
      const arr = map.get(monthKey) ?? [];
      arr.push(day);
      map.set(monthKey, arr);
    }
    return [...map.entries()]
      .sort(([a], [b]) => b.localeCompare(a))
      .map(([monthKey, days]) => {
        const [y, m] = monthKey.split("-").map(Number);
        const label = new Intl.DateTimeFormat(locale === "cs" ? "cs-CZ" : "en-GB", {
          month: "long",
          year: "numeric",
        }).format(new Date(y || 2026, (m || 1) - 1, 1));
        return { id: monthKey, label, counts: sumAbsenceDays(days) };
      });
  }, [absences.absences, locale]);

  const summaryParts = [
    totals.unsolved > 0 ? `${t("absence.unsolved")} ${totals.unsolved}` : null,
    totals.ok > 0 ? `${t("absence.ok")} ${totals.ok}` : null,
    totals.missed > 0 ? `${t("absence.missed")} ${totals.missed}` : null,
    totals.late > 0 ? `${t("absence.late")} ${totals.late}` : null,
    totals.soon > 0 ? `${t("absence.soon")} ${totals.soon}` : null,
    totals.school > 0 ? `${t("absence.school")} ${totals.school}` : null,
    threshold != null ? t("absence.limit", { limit: Math.round(threshold) }) : null,
  ].filter(Boolean);

  return (
    <div className="page-scroll">
      {/* Absence Hero */}
      <div style={{ marginBottom: "24px" }}>
        <div className="hero-stat-label">{t("absence.totalAbsence")}</div>
        <div className="hero-stat-row">
          <span className="hero-stat-number" style={{ color: "var(--brand-primary)" }}>
            {totals.total}
          </span>
          <span style={{ fontSize: "20px", fontWeight: 600, color: "var(--text-secondary)" }}>
            {t("absence.hours")}
          </span>
        </div>
        {summaryParts.length > 0 && (
          <div style={{ fontSize: "14px", color: "var(--text-secondary)", marginTop: "6px" }}>
            {summaryParts.join(" · ")}
          </div>
        )}
      </div>

      {/* Segment Switch */}
      <div style={{ marginBottom: "20px" }}>
        <div className="segmented-control">
          {(["subjects", "days", "months"] as const).map((seg) => (
            <button
              key={seg}
              type="button"
              className="segmented-btn"
              data-active={segment === seg}
              onClick={() => setSegment(seg)}
            >
              {t(`absence.segment.${seg}`)}
            </button>
          ))}
        </div>
      </div>

      {segment === "subjects" &&
        (subjectRisks.length === 0 ? (
          <EmptyState icon="calendar-remove-02" title={t("absence.empty.subjects")} />
        ) : (
          <div className="plain-rows">
            {subjectRisks.map((row) => {
              const pctText = (
                locale === "cs"
                  ? row.percentage.toFixed(1).replace(".", ",")
                  : row.percentage.toFixed(1)
              ) + " %";
              const pctColor =
                row.level === "overLimit" || row.level === "high"
                  ? "var(--band-poor)"
                  : row.level === "watch"
                    ? "var(--accent-orange)"
                    : "var(--brand-primary)";

              return (
                <div
                  key={row.id}
                  className="plain-row"
                  style={{ flexDirection: "column", alignItems: "stretch", gap: "8px" }}
                >
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "baseline",
                    }}
                  >
                    <span style={{ fontSize: "15.5px", fontWeight: 600 }}>{row.subjectName}</span>
                    <span
                      className="tabular"
                      style={{ fontSize: "16px", fontWeight: 700, color: pctColor }}
                    >
                      {pctText}
                    </span>
                  </div>

                  <RiskCapsuleBar
                    percentage={row.percentage}
                    threshold={row.threshold}
                    level={row.level}
                  />

                  <div
                    className="tabular"
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      fontSize: "12.5px",
                      color: "var(--text-secondary)",
                    }}
                  >
                    <span>
                      {t("absence.missedOfTotal", {
                        missed: row.missedLessons,
                        total: row.totalLessons,
                      })}
                    </span>
                    <span>
                      {row.threshold == null
                        ? t("absence.noThreshold")
                        : row.level === "overLimit"
                          ? t("absence.overLimit")
                          : row.missesUntilLimit != null
                            ? t("absence.untilLimit", { count: row.missesUntilLimit })
                            : ""}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        ))}

      {segment === "days" &&
        (absences.absences.length === 0 ? (
          <EmptyState icon="calendar-03" title={t("absence.empty.days")} />
        ) : (
          <div className="plain-rows">
            {[...absences.absences]
              .sort((a, b) => b.date.localeCompare(a.date))
              .map((day) => {
                const c = sumAbsenceDays([day]);
                return (
                  <div key={day.date} className="plain-row">
                    <span className="tabular" style={{ fontWeight: 600 }}>
                      {formatShortDate(day.date, locale)}
                    </span>
                    <div style={{ display: "flex", gap: "6px", flexWrap: "wrap" }}>
                      {day.ok > 0 && <StatusChip text={`${t("absence.ok")} ${day.ok}`} />}
                      {day.unsolved > 0 && (
                        <StatusChip text={`${t("absence.unsolved")} ${day.unsolved}`} />
                      )}
                      {day.missed > 0 && (
                        <StatusChip text={`${t("absence.missed")} ${day.missed}`} />
                      )}
                      {day.late > 0 && <StatusChip text={`${t("absence.late")} ${day.late}`} />}
                      {day.school > 0 && (
                        <StatusChip text={`${t("absence.school")} ${day.school}`} />
                      )}
                      <span
                        className="tabular"
                        style={{ fontWeight: 700, minWidth: "36px", textAlign: "right" }}
                      >
                        {c.total} h
                      </span>
                    </div>
                  </div>
                );
              })}
          </div>
        ))}

      {segment === "months" &&
        (monthRows.length === 0 ? (
          <EmptyState icon="calendar-03" title={t("absence.empty.months")} />
        ) : (
          <div className="plain-rows">
            <div className="plain-row" style={{ fontWeight: 700 }}>
              <span>{t("absence.totalRow")}</span>
              <span className="tabular">{totals.total} h</span>
            </div>
            {monthRows.map((m) => (
              <div key={m.id} className="plain-row">
                <span style={{ fontWeight: 600, textTransform: "capitalize" }}>{m.label}</span>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  {m.counts.ok > 0 && (
                    <StatusChip text={`${t("absence.ok")} ${m.counts.ok}`} />
                  )}
                  {m.counts.unsolved > 0 && (
                    <StatusChip text={`${t("absence.unsolved")} ${m.counts.unsolved}`} />
                  )}
                  <span className="tabular" style={{ fontWeight: 700, minWidth: "40px", textAlign: "right" }}>
                    {m.counts.total} h
                  </span>
                </div>
              </div>
            ))}
          </div>
        ))}
    </div>
  );
}
