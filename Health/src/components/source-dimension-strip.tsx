import type { HealthSourceDimensionCard } from "../server/domain/health-hub";

function formatDateLabel(value: string | undefined): string {
  return value ? value.slice(0, 10) : "未记录";
}

export function SourceDimensionStrip({
  items
}: {
  items: HealthSourceDimensionCard[];
}) {
  return (
    <section className="source-strip">
      {items.map((item) => (
        <article key={item.key} className={`source-card source-${item.status}`}>
          <div className="source-card-head">
            <p className="source-card-label">{item.label}</p>
            <span className="mini-pill">{formatDateLabel(item.latestAt)}</span>
          </div>
          <h3>{item.highlight}</h3>
          <p>{item.summary}</p>
        </article>
      ))}
    </section>
  );
}
