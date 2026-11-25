import { useEffect, useMemo, useState } from "react";
import {
  formatAverage,
  formatWeight,
  gradeBandForAverage,
  gradeBandForMark,
  overallStudyAverage,
  prepareSubjectCalculation,
  simulateSubjectGrade,
  subjectAverage,
} from "../../shared/schoolMath.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type { MarksSnapshot, SubjectMarks } from "../../shared/types.ts";
import {
  EmptyState,
  formatShortDate,
  GradeBadge,
  Icon,
  PlainSection,
  StatusChip,
} from "../components/Primitives.tsx";

type SortMode = "average" | "name" | "marks";

interface MarksSectionViewProps {
  marks: MarksSnapshot;
  locale: WebLocale;
  initialSubjectId?: string | null;
}

export function MarksSectionView({
  marks,
  locale,
  initialSubjectId,
}: MarksSectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const [sortMode, setSortMode] = useState<SortMode>("average");
  const [selectedSubjectId, setSelectedSubjectId] = useState<string | null>(
    initialSubjectId ?? marks.subjects[0]?.id ?? null,
  );
  const [hypotheticalMark, setHypotheticalMark] = useState<string>("");
  const [hypotheticalWeight, setHypotheticalWeight] = useState<number>(2);

  useEffect(() => {
    if (initialSubjectId && marks.subjects.some((s) => s.id === initialSubjectId)) {
      setSelectedSubjectId(initialSubjectId);
    }
  }, [initialSubjectId, marks.subjects]);

  const sortedSubjects = useMemo(() => {
    const copy = [...marks.subjects];
    if (sortMode === "name") {
      return copy.sort((a, b) => a.subjectInfo.name.localeCompare(b.subjectInfo.name, "cs"));
    }
    if (sortMode === "marks") {
      return copy.sort((a, b) => b.marks.length - a.marks.length);
    }
    return copy.sort((a, b) => {
      const avgA = subjectAverage(a) ?? Number.MAX_SAFE_INTEGER;
      const avgB = subjectAverage(b) ?? Number.MAX_SAFE_INTEGER;
      if (avgA === avgB) {
        return a.subjectInfo.name.localeCompare(b.subjectInfo.name, "cs");
      }
      return avgB - avgA; // Highest numeric average (needs most focus in 1-5 grading) first
    });
  }, [marks.subjects, sortMode]);

  useEffect(() => {
    if (!sortedSubjects.some((s) => s.id === selectedSubjectId)) {
      setSelectedSubjectId(sortedSubjects[0]?.id ?? null);
    }
  }, [sortedSubjects, selectedSubjectId]);

  const totalMarksCount = useMemo(
    () => marks.subjects.reduce((sum, s) => sum + s.marks.length, 0),
    [marks.subjects],
  );
  const studyAvg = useMemo(() => overallStudyAverage(marks.subjects), [marks.subjects]);

  const selectedSubject: SubjectMarks | undefined = sortedSubjects.find(
    (s) => s.id === selectedSubjectId,
  );

  if (marks.subjects.length === 0) {
    return (
      <div className="page-scroll">
        <EmptyState
          icon="analytics-01"
          title={t("marks.empty.title")}
          description={t("marks.empty.body")}
        />
      </div>
    );
  }

  return (
    <div className="split-pane">
      {/* Subject Master Column */}
      <aside className="split-master">
        <div style={{ marginBottom: "22px" }}>
          <div className="hero-stat-label">{t("marks.studyAverage")}</div>
          <div className="hero-stat-row">
            <span
              className="hero-stat-number"
              style={{ color: `var(--band-${gradeBandForAverage(studyAvg)})` }}
            >
              {formatAverage(studyAvg, locale)}
            </span>
            <span style={{ fontSize: "13.5px", color: "var(--text-secondary)" }}>
              {t("marks.summary", {
                subjects: marks.subjects.length,
                marks: totalMarksCount,
              })}
            </span>
          </div>
        </div>

        <div style={{ marginBottom: "14px" }}>
          <div className="segmented-control">
            {(["average", "name", "marks"] as const).map((mode) => (
              <button
                key={mode}
                type="button"
                className="segmented-btn"
                data-active={sortMode === mode}
                onClick={() => setSortMode(mode)}
              >
                {t(`marks.sort.${mode}`)}
              </button>
            ))}
          </div>
        </div>

        <div className="plain-rows">
          {sortedSubjects.map((subject) => {
            const avg = subjectAverage(subject);
            const band = gradeBandForAverage(avg);
            return (
              <button
                key={subject.id}
                type="button"
                className="plain-row-interactive"
                data-selected={subject.id === selectedSubject?.id}
                onClick={() => {
                  setSelectedSubjectId(subject.id);
                  setHypotheticalMark("");
                }}
              >
                <div style={{ minWidth: 0 }}>
                  <div
                    style={{
                      fontSize: "15px",
                      fontWeight: 600,
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {subject.subjectInfo.name}
                  </div>
                  <div style={{ fontSize: "12.5px", color: "var(--text-secondary)", marginTop: "2px" }}>
                    {subject.pointsOnly
                      ? t("marks.detail.pointsOnly")
                      : `${subject.subjectInfo.abbrev} · ${subject.marks.length}`}
                  </div>
                </div>
                <GradeBadge text={formatAverage(avg, locale)} band={band} size="sm" />
              </button>
            );
          })}
        </div>
      </aside>

      {/* Selected Subject Detail Column */}
      <div className="split-detail">
        {selectedSubject && (
          <SubjectDetailPane
            subject={selectedSubject}
            locale={locale}
            hypotheticalMark={hypotheticalMark}
            onChangeHypotheticalMark={setHypotheticalMark}
            hypotheticalWeight={hypotheticalWeight}
            onChangeHypotheticalWeight={setHypotheticalWeight}
          />
        )}
      </div>
    </div>
  );
}

function SubjectDetailPane({
  subject,
  locale,
  hypotheticalMark,
  onChangeHypotheticalMark,
  hypotheticalWeight,
  onChangeHypotheticalWeight,
}: {
  subject: SubjectMarks;
  locale: WebLocale;
  hypotheticalMark: string;
  onChangeHypotheticalMark: (val: string) => void;
  hypotheticalWeight: number;
  onChangeHypotheticalWeight: (w: number) => void;
}) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const prepared = useMemo(() => prepareSubjectCalculation(subject), [subject]);
  const displayAverage = prepared.officialAverage ?? prepared.calculatedAverage;
  const simulation = useMemo(
    () =>
      hypotheticalMark.trim()
        ? simulateSubjectGrade(prepared, hypotheticalMark, hypotheticalWeight)
        : null,
    [prepared, hypotheticalMark, hypotheticalWeight],
  );

  const sortedMarks = useMemo(
    () => [...subject.marks].sort((a, b) => (b.markDate || "").localeCompare(a.markDate || "")),
    [subject.marks],
  );

  return (
    <div>
      <h2
        style={{
          fontSize: "28px",
          fontWeight: 700,
          letterSpacing: "-0.02em",
          margin: "0 0 18px",
        }}
      >
        {subject.subjectInfo.name}
      </h2>

      {/* Average Hero */}
      <div style={{ marginBottom: "28px" }}>
        <div className="hero-stat-label">
          {prepared.officialAverage != null
            ? t("marks.detail.schoolAverage")
            : t("marks.detail.calculatedAverage")}
        </div>
        <div className="hero-stat-row">
          <span
            className="hero-stat-number"
            style={{ color: `var(--band-${gradeBandForAverage(displayAverage)})` }}
          >
            {formatAverage(displayAverage, locale)}
          </span>
          {subject.temporaryMark && (
            <StatusChip
              text={t("marks.detail.temporaryMark", { mark: subject.temporaryMark })}
            />
          )}
        </div>
        {subject.subjectNote && (
          <div style={{ fontSize: "13.5px", color: "var(--text-secondary)", marginTop: "8px" }}>
            {subject.subjectNote}
          </div>
        )}
      </div>

      {/* Marks List */}
      <PlainSection title={t("marks.detail.marksSection")}>
        {sortedMarks.length === 0 ? (
          <div className="plain-row" style={{ color: "var(--text-secondary)" }}>
            {t("marks.detail.noMarksInSubject")}
          </div>
        ) : (
          sortedMarks.map((mark) => {
            const resolvedWeight = prepared.resolvedWeights[mark.id];
            const caption = mark.caption?.trim() || mark.theme?.trim() || t("marks.detail.untitled");
            const showTheme =
              mark.caption?.trim() &&
              mark.theme?.trim() &&
              mark.caption.trim() !== mark.theme.trim();
            const typeLabel =
              mark.typeNote &&
              mark.typeNote.trim().length > 1 &&
              mark.typeNote.trim().toLowerCase() !== caption.toLowerCase()
                ? mark.typeNote.trim()
                : null;

            return (
              <div key={mark.id} className="plain-row" style={{ alignItems: "flex-start" }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "7px" }}>
                    <span style={{ fontSize: "15.5px", fontWeight: 600 }}>{caption}</span>
                    {mark.isNew && (
                      <span
                        style={{
                          width: "7px",
                          height: "7px",
                          borderRadius: "50%",
                          background: "var(--brand-primary)",
                          display: "inline-block",
                        }}
                      />
                    )}
                  </div>

                  {showTheme && (
                    <div
                      style={{
                        fontSize: "13.5px",
                        color: "var(--text-secondary)",
                        marginTop: "3px",
                      }}
                    >
                      {mark.theme}
                    </div>
                  )}

                  <div
                    className="tabular"
                    style={{
                      fontSize: "12.5px",
                      color: "var(--text-secondary)",
                      marginTop: "5px",
                      display: "flex",
                      flexWrap: "wrap",
                      gap: "6px",
                      alignItems: "center",
                    }}
                  >
                    <span>{formatShortDate(mark.markDate, locale)}</span>
                    {typeLabel && (
                      <>
                        <span>·</span>
                        <span>{typeLabel}</span>
                      </>
                    )}
                    {!mark.isPoints && resolvedWeight && resolvedWeight.value !== 1 && (
                      <StatusChip
                        text={
                          resolvedWeight.source === "inferred"
                            ? t("marks.detail.weightEstimated", {
                                weight: formatWeight(resolvedWeight.value),
                              })
                            : t("marks.detail.weight", {
                                weight: formatWeight(resolvedWeight.value),
                              })
                        }
                      />
                    )}
                  </div>
                </div>

                <GradeBadge
                  text={
                    mark.isPoints && mark.maxPoints != null
                      ? `${mark.markText}/${mark.maxPoints}`
                      : mark.markText
                  }
                  band={gradeBandForMark(mark)}
                />
              </div>
            );
          })
        )}
      </PlainSection>

      {/* What-if Theoretical Calculator */}
      {prepared.canSimulate && (
        <PlainSection title={t("marks.simulator.title")}>
          <div style={{ padding: "14px 2px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
              <input
                type="text"
                className="brand-input"
                placeholder={t("marks.simulator.placeholder")}
                value={hypotheticalMark}
                onChange={(e) => onChangeHypotheticalMark(e.target.value)}
                style={{ width: "210px" }}
              />

              <div style={{ display: "inline-flex", alignItems: "center", gap: "6px" }}>
                <button
                  type="button"
                  className="icon-btn"
                  disabled={hypotheticalWeight <= 1}
                  onClick={() => onChangeHypotheticalWeight(Math.max(1, hypotheticalWeight - 1))}
                >
                  <Icon name="minus-sign" size={14} />
                </button>
                <span
                  className="tabular"
                  style={{ fontSize: "13.5px", fontWeight: 600, minWidth: "74px", textAlign: "center" }}
                >
                  {t("marks.simulator.weightLabel")} {hypotheticalWeight}
                </span>
                <button
                  type="button"
                  className="icon-btn"
                  disabled={hypotheticalWeight >= 10}
                  onClick={() => onChangeHypotheticalWeight(Math.min(10, hypotheticalWeight + 1))}
                >
                  <Icon name="add-01" size={14} />
                </button>
              </div>
            </div>

            {simulation && (
              <div
                className="tabular"
                style={{
                  marginTop: "12px",
                  display: "flex",
                  alignItems: "baseline",
                  gap: "10px",
                  fontSize: "16px",
                  fontWeight: 700,
                }}
              >
                <span>→ {formatAverage(simulation.estimatedAverage, locale)}</span>
                {simulation.difference != null && (
                  <span
                    style={{
                      fontSize: "13.5px",
                      fontWeight: 600,
                      color:
                        simulation.difference < -0.005
                          ? "var(--band-excellent)"
                          : simulation.difference > 0.005
                            ? "var(--band-poor)"
                            : "var(--text-secondary)",
                    }}
                  >
                    {simulation.difference < -0.005
                      ? t("marks.simulator.better", {
                          delta: formatAverage(Math.abs(simulation.difference), locale),
                        })
                      : simulation.difference > 0.005
                        ? t("marks.simulator.worse", {
                            delta: formatAverage(simulation.difference, locale),
                          })
                        : t("marks.simulator.same")}
                  </span>
                )}
              </div>
            )}

            <div style={{ fontSize: "12px", color: "var(--text-tertiary)", marginTop: "8px" }}>
              {t("marks.simulator.readOnlyHint")}
            </div>
          </div>
        </PlainSection>
      )}
    </div>
  );
}
