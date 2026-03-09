import type { AnnualExamView } from "../server/domain/health-hub";

function formatValue(value: number | undefined, unit: string) {
  if (typeof value !== "number") {
    return "--";
  }

  const digits = unit === "kg" ? 1 : ["mmol/L", "%", "g/L"].includes(unit) ? 2 : 0;
  return `${value.toFixed(digits)} ${unit}`;
}

function formatDelta(value: number | undefined, unit: string) {
  if (typeof value !== "number") {
    return "无同比";
  }

  const digits = unit === "kg" ? 1 : ["mmol/L", "%", "g/L"].includes(unit) ? 2 : 0;
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(digits)} ${unit}`;
}

export function AnnualExamPanel({ exam }: { exam?: AnnualExamView }) {
  if (!exam) {
    return (
      <section className="panel-card">
        <div className="panel-head">
          <div>
            <p className="panel-kicker">Annual Exam</p>
            <h2>年度体检综合</h2>
            <p className="panel-description">当前还没有可展示的年度体检摘要。</p>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section className="panel-card exam-panel">
      <div className="panel-head">
        <div>
          <p className="panel-kicker">Annual Exam</p>
          <h2>{exam.latestTitle}</h2>
          <p className="panel-description">{exam.highlightSummary}</p>
        </div>
        <div className="summary-meta">
          <span>{exam.latestRecordedAt.slice(0, 10)}</span>
          {exam.previousTitle ? <span>{exam.previousTitle}</span> : null}
        </div>
      </div>

      <div className="exam-summary-row">
        <article className="exam-summary-card">
          <p className="exam-summary-label">本次体检重点</p>
          <h3>{exam.abnormalMetricLabels.length > 0 ? exam.abnormalMetricLabels.join("、") : "无新增异常"}</h3>
          <p>{exam.actionSummary}</p>
        </article>
        <article className="exam-summary-card">
          <p className="exam-summary-label">相较上一年度</p>
          <h3>{exam.improvedMetricLabels.length > 0 ? exam.improvedMetricLabels.join("、") : "整体平稳"}</h3>
          <p>用年度基线理解近期复查和行为变化是否真的有效。</p>
        </article>
      </div>

      <div className="exam-metric-grid">
        {exam.metrics.map((metric) => (
          <article
            key={metric.metricCode}
            className={`exam-metric-card flag-${metric.abnormalFlag}`}
          >
            <div className="exam-metric-head">
              <div>
                <p className="exam-metric-label">{metric.label}</p>
                <h3>{formatValue(metric.latestValue, metric.unit)}</h3>
              </div>
              <span className="mini-pill">{metric.abnormalFlag}</span>
            </div>
            <div className="exam-comparison-lane">
              <div>
                <span>2025</span>
                <strong>{formatValue(metric.latestValue, metric.unit)}</strong>
              </div>
              <div className="comparison-arrow" />
              <div>
                <span>2024</span>
                <strong>{formatValue(metric.previousValue, metric.unit)}</strong>
              </div>
            </div>
            <p className="exam-delta">同比 {formatDelta(metric.delta, metric.unit)}</p>
            {metric.meaning ? (
              <p className="exam-note">
                <strong>含义：</strong>
                {metric.meaning}
              </p>
            ) : null}
            {metric.referenceRange ? (
              <p className="exam-reference">参考范围 {metric.referenceRange}</p>
            ) : null}
            {metric.practicalAdvice ? (
              <p className="exam-guidance">
                <strong>建议：</strong>
                {metric.practicalAdvice}
              </p>
            ) : null}
          </article>
        ))}
      </div>
    </section>
  );
}
