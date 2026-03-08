import type { HealthOverviewSpotlight } from "../server/domain/health-hub";

export function OverviewSpotlightGrid({
  items
}: {
  items: HealthOverviewSpotlight[];
}) {
  return (
    <div className="spotlight-grid">
      {items.map((item) => (
        <article key={item.label} className={`spotlight-card tone-${item.tone}`}>
          <p className="spotlight-label">{item.label}</p>
          <h3>{item.value}</h3>
          <p>{item.detail}</p>
        </article>
      ))}
    </div>
  );
}
