import type { HealthReportSnapshotRecord } from "../server/domain/health-hub";

function sectionList(title: string, items: string[]) {
  return (
    <section className="report-section" key={title}>
      <h3>{title}</h3>
      <ul className="summary-list">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </section>
  );
}

export function ReportDetail({ report }: { report: HealthReportSnapshotRecord }) {
  const topInsights = report.structuredInsights.insights.slice(0, 5);
  const topMetrics = report.structuredInsights.metric_summaries.slice(0, 8);

  return (
    <article className="report-detail">
      <header className="report-detail-hero">
        <div>
          <p className="report-type">{report.reportType === "weekly" ? "周报" : "月报"}</p>
          <h1>{report.title}</h1>
          <p className="report-headline">{report.summary.output.headline}</p>
        </div>
        <div className="report-meta-box">
          <p>生成时间 {new Date(report.createdAt).toLocaleString("zh-CN")}</p>
          <p>LLM provider {report.summary.provider}</p>
          <p>Prompt {report.summary.prompt.templateId}:{report.summary.prompt.version}</p>
        </div>
      </header>

      <div className="report-detail-grid">
        {sectionList("本期变化概览", report.summary.output.most_important_changes)}
        {sectionList("可能原因", report.summary.output.possible_reasons)}
        {sectionList("建议优先行动", report.summary.output.priority_actions)}
        {sectionList("可继续观察项", report.summary.output.continue_observing)}
      </div>

      <section className="report-detail-grid">
        <section className="report-section">
          <h3>结构化风险提示</h3>
          <div className="stack-list">
            {topInsights.map((insight) => (
              <article key={insight.id} className={`reminder-card severity-${insight.severity}`}>
                <h4>{insight.title}</h4>
                <p>{insight.evidence.summary}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="report-section">
          <h3>指标变化摘要</h3>
          <div className="metric-stack">
            {topMetrics.map((metric) => (
              <article key={metric.metric_code} className="metric-mini-card">
                <h4>{metric.metric_name}</h4>
                <p>
                  {metric.latest_value} {metric.unit}
                </p>
                <p>趋势 {metric.trend_direction ?? "n/a"}</p>
                <p>环比 {metric.month_over_month ?? "n/a"}</p>
              </article>
            ))}
          </div>
        </section>
      </section>

      <p className="summary-disclaimer">{report.summary.output.disclaimer}</p>
    </article>
  );
}
