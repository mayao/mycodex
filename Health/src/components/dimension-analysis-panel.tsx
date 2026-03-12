import type { HealthDimensionAnalysis } from "../server/domain/health-hub";

function renderItems(items: string[]) {
  return (
    <ul className="analysis-list">
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  );
}

export function DimensionAnalysisPanel({
  analysis
}: {
  analysis: HealthDimensionAnalysis;
}) {
  return (
    <section className={`analysis-panel analysis-${analysis.key}`}>
      <div className="analysis-panel-head">
        <div>
          <p className="panel-kicker">{analysis.kicker}</p>
          <h2>{analysis.title}</h2>
          <p className="panel-description">{analysis.summary}</p>
        </div>
      </div>

      <div className="analysis-metric-grid">
        {analysis.metrics.map((metric) => (
          <article key={`${analysis.key}-${metric.label}`} className={`analysis-metric-card tone-${metric.tone}`}>
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
            <p>{metric.detail}</p>
          </article>
        ))}
      </div>

      <div className="analysis-grid">
        <article className="analysis-card tone-positive">
          <div className="analysis-card-head">
            <p>做得好的地方</p>
            <span>{analysis.goodSignals.length}</span>
          </div>
          {renderItems(analysis.goodSignals)}
        </article>

        <article className="analysis-card tone-attention">
          <div className="analysis-card-head">
            <p>需要继续关注</p>
            <span>{analysis.needsAttention.length}</span>
          </div>
          {renderItems(analysis.needsAttention)}
        </article>

        <article className="analysis-card tone-risk">
          <div className="analysis-card-head">
            <p>长期背景与风险</p>
            <span>{analysis.longTermRisks.length}</span>
          </div>
          {renderItems(analysis.longTermRisks)}
        </article>

        <article className="analysis-card tone-neutral">
          <div className="analysis-card-head">
            <p>建议怎么做</p>
            <span>{analysis.actionPlan.length}</span>
          </div>
          {renderItems(analysis.actionPlan)}
        </article>
      </div>
    </section>
  );
}
