import type {
  HealthOverviewDigest,
  HealthOverviewSpotlight,
  HealthSourceDimensionCard
} from "../server/domain/health-hub";

interface OverviewCommandCenterProps {
  digest: HealthOverviewDigest;
  focusAreas: string[];
  spotlights: HealthOverviewSpotlight[];
  sources: HealthSourceDimensionCard[];
}

function renderList(title: string, items: string[], tone: "positive" | "attention" | "risk" | "neutral") {
  return (
    <article className={`command-column tone-${tone}`}>
      <div className="command-column-head">
        <p>{title}</p>
        <span>{items.length}</span>
      </div>
      <ul className="command-list">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </article>
  );
}

export function OverviewCommandCenter({
  digest,
  focusAreas,
  spotlights,
  sources
}: OverviewCommandCenterProps) {
  return (
    <section className="command-center-panel">
      <div className="command-center-hero">
        <div className="command-copy">
          <p className="panel-kicker">Health Overview</p>
          <div className="command-headline-card">
            <span>当前综合判断</span>
            <strong>{digest.headline}</strong>
          </div>
          <p className="command-summary">{digest.summary}</p>

          <div className="focus-chip-row command-focus-row">
            {focusAreas.map((item) => (
              <span key={item} className="focus-chip">
                {item}
              </span>
            ))}
          </div>

          <div className="command-grid">
            {renderList("现在做得好的部分", digest.goodSignals, "positive")}
            {renderList("当前需要继续盯住", digest.needsAttention, "attention")}
            {renderList("长期背景与风险", digest.longTermRisks, "risk")}
            {renderList("下一步最值得做", digest.actionPlan, "neutral")}
          </div>
        </div>

        <div className="command-side">
          <div className="command-spotlight-grid">
            {spotlights.map((item) => (
              <article key={item.label} className={`command-spotlight tone-${item.tone}`}>
                <p>{item.label}</p>
                <strong>{item.value}</strong>
                <span>{item.detail}</span>
              </article>
            ))}
          </div>

          <div className="command-source-list">
            {sources.map((item) => (
              <article key={item.key} className={`command-source-card source-${item.status}`}>
                <div>
                  <p>{item.label}</p>
                  <strong>{item.highlight}</strong>
                </div>
                <span>{item.latestAt ? item.latestAt.slice(0, 10) : "未记录"}</span>
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
