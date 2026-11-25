import type { ReactNode } from "react";
import type { AbsenceRiskLevel, GradeBand } from "../../shared/types.ts";

export function Icon({
  name,
  size = 17,
  className = "",
  color,
}: {
  name: string;
  size?: number;
  className?: string;
  color?: string;
}) {
  return (
    <span
      className={`hgi-icon ${className}`.trim()}
      style={{
        fontSize: `${size}px`,
        width: `${size}px`,
        height: `${size}px`,
        color,
      }}
      aria-hidden="true"
    >
      {name}
    </span>
  );
}

export function GradeyWordmark({ width = 112, height = 30 }: { width?: number; height?: number }) {
  return (
    <span
      className="gradey-wordmark"
      style={{ width: `${width}px`, height: `${height}px` }}
      role="img"
      aria-label="Gradey"
    />
  );
}

export function GradeBadge({
  text,
  band,
  size = "regular",
}: {
  text: string;
  band: GradeBand;
  size?: "sm" | "regular";
}) {
  return (
    <span className="grade-badge" data-band={band} data-size={size}>
      {text}
    </span>
  );
}

export function StatusChip({
  text,
  color,
  background,
}: {
  text: string;
  color?: string;
  background?: string;
}) {
  return (
    <span className="status-chip" style={{ color, background }}>
      {text}
    </span>
  );
}

export function RiskCapsuleBar({
  percentage,
  threshold,
  level,
}: {
  percentage: number;
  threshold: number | null;
  level: AbsenceRiskLevel;
}) {
  const denom = threshold && threshold > 0 ? threshold : 100;
  const widthPct = Math.min(100, Math.max(percentage > 0 ? 3 : 0, (percentage / denom) * 100));
  const color =
    threshold == null
      ? "var(--text-tertiary)"
      : level === "overLimit" || level === "high"
        ? "var(--band-poor)"
        : level === "watch"
          ? "var(--accent-orange)"
          : "var(--brand-primary)";

  return (
    <div className="risk-capsule-track" aria-hidden="true">
      <div
        className="risk-capsule-fill"
        style={{ width: `${widthPct}%`, backgroundColor: color }}
      />
    </div>
  );
}

export function PlainSection({
  title,
  actionLabel,
  onAction,
  children,
}: {
  title?: string;
  actionLabel?: string;
  onAction?: () => void;
  children: ReactNode;
}) {
  return (
    <section className="plain-section">
      {title && (
        <div className="plain-section-header">
          <h2 className="plain-section-title">{title}</h2>
          {actionLabel && onAction && (
            <button type="button" className="plain-section-link" onClick={onAction}>
              <span>{actionLabel}</span>
              <Icon name="arrow-right-01" size={14} />
            </button>
          )}
        </div>
      )}
      <div className="plain-rows">{children}</div>
    </section>
  );
}

export function EmptyState({
  icon,
  title,
  description,
  actionLabel,
  onAction,
}: {
  icon: string;
  title: string;
  description?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <div
      style={{
        padding: "56px 24px",
        textAlign: "center",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: "10px",
      }}
    >
      <Icon name={icon} size={28} color="var(--text-tertiary)" />
      <div style={{ fontSize: "16px", fontWeight: 600 }}>{title}</div>
      {description && (
        <div style={{ fontSize: "14px", color: "var(--text-secondary)", maxWidth: "400px" }}>
          {description}
        </div>
      )}
      {actionLabel && onAction && (
        <button
          type="button"
          className="icon-btn"
          style={{ marginTop: "8px" }}
          onClick={onAction}
        >
          <Icon name="refresh-04" size={15} />
          <span>{actionLabel}</span>
        </button>
      )}
    </div>
  );
}

export function formatShortDate(rawIso: string | null | undefined, locale: "en" | "cs"): string {
  if (!rawIso) return "";
  const parsed = new Date(rawIso);
  if (Number.isNaN(parsed.getTime())) return rawIso.slice(0, 10);
  return new Intl.DateTimeFormat(locale === "cs" ? "cs-CZ" : "en-GB", {
    day: "numeric",
    month: "numeric",
  }).format(parsed);
}

export function formatDateTime(rawIso: string | null | undefined, locale: "en" | "cs"): string {
  if (!rawIso) return "";
  const parsed = new Date(rawIso);
  if (Number.isNaN(parsed.getTime())) return rawIso;
  return new Intl.DateTimeFormat(locale === "cs" ? "cs-CZ" : "en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(parsed);
}
