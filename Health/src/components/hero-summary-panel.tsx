import type {
  GeneticFindingView,
  HealthReminderItem,
  HealthReportSnapshotRecord,
  HealthSummaryGenerationResult
} from "../server/domain/health-hub";

interface HeroSummaryPanelProps {
  summary: HealthSummaryGenerationResult;
  reminders: HealthReminderItem[];
  watchItems: HealthReminderItem[];
  geneticFindings: GeneticFindingView[];
  latestReports: HealthReportSnapshotRecord[];
}

function uniqueItems(items: string[], limit: number): string[] {
  return [...new Set(items.map((item) => item.trim()).filter(Boolean))].slice(0, limit);
}

function renderCompactList(items: string[]) {
  if (items.length === 0) {
    return <p className="summary-empty">暂无结构化内容。</p>;
  }

  return (
    <ul className="summary-list compact-list-body">
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  );
}

export function HeroSummaryPanel({
  summary,
  reminders,
  watchItems,
  geneticFindings,
  latestReports
}: HeroSummaryPanelProps) {
  const dimensionCount = new Set(geneticFindings.map((item) => item.dimension)).size;
  const leadReminder = reminders[0];
  const observeItems = uniqueItems(
    [
      ...summary.output.continue_observing,
      ...watchItems.slice(0, 2).map((item) => item.title)
    ],
    3
  );
  const signals = [
    {
      label: "结构化提醒",
      value: `${reminders.length}`,
      detail: "当前决策优先级"
    },
    {
      label: "优先动作",
      value: `${summary.output.priority_actions.length}`,
      detail: "可直接执行"
    },
    {
      label: "观察项",
      value: `${watchItems.length}`,
      detail: "需继续跟踪"
    },
    {
      label: "基因维度",
      value: `${dimensionCount}`,
      detail: `${geneticFindings.length} 条背景`
    }
  ];

  return (
    <div className="hero-side hero-summary-side">
      <div className="hero-summary-top">
        <div>
          <p className="panel-kicker">本期摘要</p>
          <h3>{summary.output.headline}</h3>
        </div>
        <div className="hero-summary-meta">
          <span>{summary.provider}</span>
          <span>{summary.prompt.version}</span>
          <span>{latestReports.length} 份快照</span>
        </div>
      </div>

      {leadReminder ? (
        <section className="hero-summary-banner">
          <span className="hero-summary-banner-label">当前主线</span>
          <strong>{leadReminder.title}</strong>
          {leadReminder.indicatorMeaning ? <p>{leadReminder.indicatorMeaning}</p> : null}
          <p>{leadReminder.suggested_action}</p>
        </section>
      ) : null}

      <div className="hero-summary-signal-grid">
        {signals.map((signal) => (
          <article key={signal.label} className="hero-signal-card">
            <span>{signal.label}</span>
            <strong>{signal.value}</strong>
            <p>{signal.detail}</p>
          </article>
        ))}
      </div>

      <div className="hero-summary-columns">
        <article className="hero-summary-section">
          <h4>关键变化</h4>
          {renderCompactList(summary.output.most_important_changes.slice(0, 2))}
        </article>

        <article className="hero-summary-section">
          <h4>可能原因</h4>
          {renderCompactList(summary.output.possible_reasons.slice(0, 2))}
        </article>

        <article className="hero-summary-section">
          <h4>优先动作</h4>
          {renderCompactList(summary.output.priority_actions.slice(0, 3))}
        </article>

        <article className="hero-summary-section">
          <h4>继续观察</h4>
          {renderCompactList(observeItems)}
        </article>
      </div>

      <p className="summary-disclaimer">{summary.output.disclaimer}</p>
    </div>
  );
}
