import type { HealthSummaryGenerationResult } from "../server/domain/health-hub";

interface SummaryCardProps {
  eyebrow: string;
  title: string;
  summary: HealthSummaryGenerationResult;
  focusAreas?: string[];
}

function renderList(items: string[]) {
  if (items.length === 0) {
    return <p className="summary-empty">暂无结构化内容。</p>;
  }

  return (
    <ul className="summary-list">
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  );
}

export function SummaryCard({ eyebrow, title, summary, focusAreas = [] }: SummaryCardProps) {
  const stats = [
    { label: "变化", value: summary.output.most_important_changes.length },
    { label: "原因", value: summary.output.possible_reasons.length },
    { label: "动作", value: summary.output.priority_actions.length },
    { label: "观察", value: summary.output.continue_observing.length }
  ];

  return (
    <section className="panel-card summary-card">
      <p className="panel-kicker">{eyebrow}</p>
      <div className="panel-head">
        <div>
          <h2>{title}</h2>
          <p className="panel-description">{summary.output.headline}</p>
          {focusAreas.length > 0 ? (
            <div className="focus-chip-row">
              {focusAreas.map((item) => (
                <span key={item} className="focus-chip">
                  {item}
                </span>
              ))}
            </div>
          ) : null}
        </div>
        <div className="summary-meta">
          <span>{summary.provider}</span>
          <span>{summary.prompt.version}</span>
        </div>
      </div>

      <div className="summary-stat-row">
        {stats.map((stat) => (
          <article key={stat.label} className="summary-stat-card">
            <span>{stat.label}</span>
            <strong>{stat.value}</strong>
          </article>
        ))}
      </div>

      <div className="summary-grid">
        <article>
          <h3>本期最重要变化</h3>
          {renderList(summary.output.most_important_changes)}
        </article>
        <article>
          <h3>可能原因</h3>
          {renderList(summary.output.possible_reasons)}
        </article>
        <article>
          <h3>建议优先行动</h3>
          {renderList(summary.output.priority_actions)}
        </article>
        <article>
          <h3>可继续观察项</h3>
          {renderList(summary.output.continue_observing)}
        </article>
      </div>

      <p className="summary-disclaimer">{summary.output.disclaimer}</p>
    </section>
  );
}
