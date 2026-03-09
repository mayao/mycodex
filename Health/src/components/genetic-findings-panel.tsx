import type { GeneticFindingView } from "../server/domain/health-hub";

function riskLabel(riskLevel: GeneticFindingView["riskLevel"]) {
  if (riskLevel === "high") {
    return "高关注";
  }

  if (riskLevel === "medium") {
    return "中等背景";
  }

  return "低背景";
}

function riskWeight(riskLevel: GeneticFindingView["riskLevel"]): number {
  if (riskLevel === "high") {
    return 3;
  }

  if (riskLevel === "medium") {
    return 2;
  }

  return 1;
}

function formatRiskRatio(count: number, total: number): string {
  if (total === 0) {
    return "0%";
  }

  return `${Math.round((count / total) * 100)}%`;
}

export function GeneticFindingsPanel({
  findings
}: {
  findings: GeneticFindingView[];
}) {
  const riskCounts = {
    high: findings.filter((item) => item.riskLevel === "high").length,
    medium: findings.filter((item) => item.riskLevel === "medium").length,
    low: findings.filter((item) => item.riskLevel === "low").length
  };
  const dimensionMap = new Map<
    string,
    { dimension: string; findings: GeneticFindingView[]; highestRisk: GeneticFindingView["riskLevel"] }
  >();

  for (const finding of findings) {
    const current = dimensionMap.get(finding.dimension);

    if (!current) {
      dimensionMap.set(finding.dimension, {
        dimension: finding.dimension,
        findings: [finding],
        highestRisk: finding.riskLevel
      });
      continue;
    }

    current.findings.push(finding);

    if (riskWeight(finding.riskLevel) > riskWeight(current.highestRisk)) {
      current.highestRisk = finding.riskLevel;
    }
  }

  const dimensionGroups = [...dimensionMap.values()].sort((left, right) => {
    const riskGap = riskWeight(right.highestRisk) - riskWeight(left.highestRisk);

    if (riskGap !== 0) {
      return riskGap;
    }

    return right.findings.length - left.findings.length;
  });
  const linkedMetricCount = findings.filter((item) => item.linkedMetricLabel).length;
  const evidenceALevelCount = findings.filter((item) => item.evidenceLevel === "A").length;

  return (
    <section className="panel-card genetic-panel">
      <div className="panel-head">
        <div>
          <p className="panel-kicker">Genetic Context</p>
          <h2>基因检测维度</h2>
          <p className="panel-description">
            不把基因 finding 当作结论，而是把它们作为长期背景，和近期化验、睡眠、运动一起解释。
          </p>
        </div>
      </div>

      <div className="genetic-overview-grid">
        <article className="genetic-stat-card">
          <span>总 finding</span>
          <strong>{findings.length}</strong>
          <p>当前用于长期背景解释</p>
        </article>
        <article className="genetic-stat-card">
          <span>覆盖维度</span>
          <strong>{dimensionGroups.length}</strong>
          <p>覆盖血脂、体重、血糖、恢复和训练</p>
        </article>
        <article className="genetic-stat-card">
          <span>高关注背景</span>
          <strong>{riskCounts.high}</strong>
          <p>需要放到长期跟踪主线里看</p>
        </article>
        <article className="genetic-stat-card">
          <span>已关联指标</span>
          <strong>{linkedMetricCount}</strong>
          <p>{evidenceALevelCount} 条为 A 级证据</p>
        </article>
      </div>

      <div className="genetic-visual-grid">
        <section className="genetic-bar-panel">
          <div className="genetic-bar-panel-head">
            <h3>风险分布</h3>
            <span>按当前 mock finding 聚合</span>
          </div>

          {(["high", "medium", "low"] as const).map((level) => (
            <div key={level} className="genetic-bar-row">
              <span>{riskLabel(level)}</span>
              <div className="genetic-bar-track">
                <div
                  className={`genetic-bar-fill bar-${level}`}
                  style={{ width: formatRiskRatio(riskCounts[level], findings.length) }}
                />
              </div>
              <strong>{riskCounts[level]}</strong>
            </div>
          ))}
        </section>

        <section className="genetic-dimension-board">
          <div className="genetic-bar-panel-head">
            <h3>关键维度汇总</h3>
            <span>把 trait 放回到实际健康决策语境里</span>
          </div>

          <div className="genetic-dimension-grid">
            {dimensionGroups.map((group) => (
              <article
                key={group.dimension}
                className={`genetic-dimension-card dimension-${group.highestRisk}`}
              >
                <div className="genetic-dimension-top">
                  <p>{group.dimension}</p>
                  <span>{group.findings.length} 条</span>
                </div>
                <strong>{group.findings[0]?.traitLabel}</strong>
                <div className="trait-chip-row">
                  {group.findings.slice(0, 3).map((finding) => (
                    <span key={finding.id} className="trait-chip">
                      {finding.traitLabel}
                    </span>
                  ))}
                </div>
              </article>
            ))}
          </div>
        </section>
      </div>

      <div className="genetic-grid">
        {findings.map((finding) => (
          <article
            key={finding.id}
            className={`genetic-card risk-${finding.riskLevel}`}
          >
            <div className="genetic-head">
              <div>
                <p className="genetic-gene">{finding.geneSymbol}</p>
                <h3>{finding.traitLabel}</h3>
              </div>
              <div className="genetic-meta">
                <span className="mini-pill">{riskLabel(finding.riskLevel)}</span>
                <span className="mini-pill">证据 {finding.evidenceLevel}</span>
              </div>
            </div>
            <p className="genetic-dimension">{finding.dimension}</p>
            <p>{finding.summary}</p>
            {finding.plainMeaning ? (
              <p className="genetic-meaning">
                <strong>这通常表示：</strong>
                {finding.plainMeaning}
              </p>
            ) : null}
            {finding.linkedMetricLabel ? (
              <div className="genetic-linked">
                <span>当前关联指标</span>
                <strong>
                  {finding.linkedMetricLabel} · {finding.linkedMetricValue}
                </strong>
                {finding.linkedMetricFlag ? (
                  <span className="mini-pill">{finding.linkedMetricFlag}</span>
                ) : null}
              </div>
            ) : null}
            <p className="genetic-action">建议：{finding.suggestion}</p>
            {finding.practicalAdvice ? (
              <p className="genetic-guidance">
                <strong>落地做法：</strong>
                {finding.practicalAdvice}
              </p>
            ) : null}
          </article>
        ))}
      </div>
    </section>
  );
}
