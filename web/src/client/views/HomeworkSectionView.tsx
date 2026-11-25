import { useEffect, useMemo, useState } from "react";
import { pragueDateString, shiftIsoDays } from "../../shared/schoolMath.ts";
import { translate, type WebLocale } from "../../shared/i18n.ts";
import type { HomeworkItem, HomeworkSnapshot } from "../../shared/types.ts";
import {
  EmptyState,
  formatShortDate,
  Icon,
  PlainSection,
  StatusChip,
} from "../components/Primitives.tsx";

type HomeworkFilter = "open" | "done" | "all";

interface HomeworkSectionViewProps {
  homeworks: HomeworkSnapshot;
  locale: WebLocale;
  initialHomeworkId?: string | null;
}

export function HomeworkSectionView({
  homeworks,
  locale,
  initialHomeworkId,
}: HomeworkSectionViewProps) {
  const t = (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
    translate(locale, key, params);

  const [filter, setFilter] = useState<HomeworkFilter>("open");
  const [selectedId, setSelectedId] = useState<string | null>(
    initialHomeworkId ?? homeworks.homeworks[0]?.id ?? null,
  );

  useEffect(() => {
    if (initialHomeworkId && homeworks.homeworks.some((h) => h.id === initialHomeworkId)) {
      setSelectedId(initialHomeworkId);
      setFilter("all");
    }
  }, [initialHomeworkId, homeworks.homeworks]);

  const filtered = useMemo(() => {
    return homeworks.homeworks
      .filter((hw) => {
        if (filter === "open") return !hw.isDone && !hw.isClosed;
        if (filter === "done") return hw.isDone || hw.isClosed;
        return true;
      })
      .sort((a, b) => (a.dueOn ?? "9999").localeCompare(b.dueOn ?? "9999"));
  }, [homeworks.homeworks, filter]);

  useEffect(() => {
    if (!filtered.some((h) => h.id === selectedId)) {
      setSelectedId(filtered[0]?.id ?? null);
    }
  }, [filtered, selectedId]);

  const selected: HomeworkItem | undefined = filtered.find((h) => h.id === selectedId);
  const todayIso = pragueDateString(new Date());
  const tomorrowIso = shiftIsoDays(todayIso, 1);

  const dueLabel = (dueOn: string | null) => {
    if (!dueOn) return null;
    const dayKey = dueOn.slice(0, 10);
    if (dayKey === todayIso) return t("homework.dueToday");
    if (dayKey === tomorrowIso) return t("homework.dueTomorrow");
    return t("homework.dueDate", { date: formatShortDate(dueOn, locale) });
  };

  return (
    <div className="split-pane">
      <aside className="split-master">
        <div style={{ marginBottom: "16px" }}>
          <div className="segmented-control">
            {(["open", "done", "all"] as const).map((f) => (
              <button
                key={f}
                type="button"
                className="segmented-btn"
                data-active={filter === f}
                onClick={() => setFilter(f)}
              >
                {t(`homework.filter.${f}`)}
              </button>
            ))}
          </div>
        </div>

        {filtered.length === 0 ? (
          <EmptyState
            icon="check-list"
            title={filter === "open" ? t("homework.empty.open") : t("homework.empty.all")}
          />
        ) : (
          <div className="plain-rows">
            {filtered.map((hw) => {
              const due = dueLabel(hw.dueOn);
              return (
                <button
                  key={hw.id}
                  type="button"
                  className="plain-row-interactive"
                  data-selected={hw.id === selected?.id}
                  onClick={() => setSelectedId(hw.id)}
                >
                  <div style={{ minWidth: 0 }}>
                    <div
                      style={{
                        fontSize: "15px",
                        fontWeight: 600,
                        textDecoration: hw.isDone ? "line-through" : "none",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                      }}
                    >
                      {hw.title}
                    </div>
                    <div
                      style={{
                        fontSize: "12.5px",
                        color: "var(--text-secondary)",
                        marginTop: "3px",
                        display: "flex",
                        alignItems: "center",
                        gap: "6px",
                      }}
                    >
                      <span>{hw.subjectName || hw.subjectAbbrev || ""}</span>
                      {due && (
                        <>
                          <span>·</span>
                          <span>{due}</span>
                        </>
                      )}
                    </div>
                  </div>
                  <Icon
                    name={hw.isDone || hw.isClosed ? "checkmark-circle-02" : "circle"}
                    size={18}
                    color={
                      hw.isDone || hw.isClosed ? "var(--brand-primary)" : "var(--text-tertiary)"
                    }
                  />
                </button>
              );
            })}
          </div>
        )}
      </aside>

      <div className="split-detail">
        {selected ? (
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "8px" }}>
              <StatusChip
                text={
                  selected.isDone
                    ? t("homework.completedBadge")
                    : selected.isClosed
                      ? t("homework.closed")
                      : t("homework.openBadge")
                }
              />
              {(selected.subjectName || selected.subjectAbbrev) && (
                <span style={{ fontSize: "14px", fontWeight: 600, color: "var(--text-secondary)" }}>
                  {selected.subjectName || selected.subjectAbbrev}
                </span>
              )}
            </div>

            <div
              style={{
                fontSize: "16px",
                lineHeight: 1.6,
                whiteSpace: "pre-wrap",
                margin: "16px 0 28px",
              }}
            >
              {linkifyText(selected.content || selected.title)}
            </div>

            <PlainSection>
              {selected.dueOn && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)" }}>
                    {dueLabel(selected.dueOn)}
                  </span>
                  <span className="tabular" style={{ fontWeight: 600 }}>
                    {formatShortDate(selected.dueOn, locale)}
                  </span>
                </div>
              )}
              {selected.assignedOn && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)" }}>
                    {t("homework.assignedDate")}
                  </span>
                  <span className="tabular" style={{ fontWeight: 600 }}>
                    {formatShortDate(selected.assignedOn, locale)}
                  </span>
                </div>
              )}
              {selected.teacherName && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)" }}>{t("homework.teacher")}</span>
                  <span style={{ fontWeight: 600 }}>{selected.teacherName}</span>
                </div>
              )}
              {selected.notice && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)" }}>{t("homework.notice")}</span>
                  <span>{selected.notice}</span>
                </div>
              )}
              {selected.isElectronic && (
                <div className="plain-row">
                  <span style={{ color: "var(--text-secondary)" }}>
                    {t("homework.electronic")}
                  </span>
                  <Icon name="checkmark-circle-02" size={16} color="var(--brand-primary)" />
                </div>
              )}
            </PlainSection>

            {selected.attachments.length > 0 && (
              <PlainSection title={t("homework.attachments")}>
                {selected.attachments.map((att) => (
                  <div key={att.id} className="plain-row">
                    <span>{att.name}</span>
                    {att.size != null && (
                      <span className="tabular" style={{ fontSize: "12.5px", color: "var(--text-secondary)" }}>
                        {Math.max(1, Math.round(att.size / 1024))} KB
                      </span>
                    )}
                  </div>
                ))}
              </PlainSection>
            )}

            <div
              style={{
                marginTop: "20px",
                fontSize: "12.5px",
                color: "var(--text-tertiary)",
                display: "flex",
                alignItems: "center",
                gap: "6px",
              }}
            >
              <Icon name="information-circle" size={14} />
              <span>{t("homework.readOnlyNote")}</span>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}

function linkifyText(text: string) {
  const urlRegex = /(https?:\/\/[^\s<]+)/g;
  const parts = text.split(urlRegex);
  return parts.map((part, idx) => {
    if (/^https?:\/\//.test(part)) {
      return (
        <a
          key={idx}
          href={part}
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: "var(--brand-primary)", textDecoration: "underline" }}
        >
          {part}
        </a>
      );
    }
    return <span key={idx}>{part}</span>;
  });
}
