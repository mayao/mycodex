import { AnnualExamPanel } from "../../components/annual-exam-panel";
import { DimensionAnalysisPanel } from "../../components/dimension-analysis-panel";
import { GeneticFindingsPanel } from "../../components/genetic-findings-panel";
import { OverviewCommandCenter } from "../../components/overview-command-center";
import { ShareReadyPanel } from "../../components/share-ready-panel";
import { SiteHeader } from "../../components/site-header";
import { TrendPanel } from "../../components/trend-panel";
import { shareHealthHomePageData } from "../../data/mock/share-page-data";

function renderNarrativeList(items: string[]) {
  return (
    <ul className="analysis-list">
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  );
}

export default function SharePage() {
  const dashboard = shareHealthHomePageData;
  const integratedAnalysis = dashboard.dimensionAnalyses.find((item) => item.key === "integrated");
  const dimensionPanels = dashboard.dimensionAnalyses.filter((item) => item.key !== "integrated");

  return (
    <main className="app-shell next-health-shell">
      <SiteHeader
        generatedAt={dashboard.generatedAt}
        kicker="Desensitized Share View"
        title="Vital Command Share"
        subtitle="用于公司内部分享的脱敏演示页。所有身份、机构、日期和背景信息均为 mock 或已做结构性调整，只保留产品表达逻辑。"
        badge="脱敏演示"
        navLinks={[
          { href: "/share", label: "分享首页" },
          { href: "/share#insight-hub", label: "结构洞察" },
          { href: "/share#visual-lab", label: "图表样例" },
          { href: "/share#brief-report", label: "报告快照" }
        ]}
      />

      <OverviewCommandCenter
        digest={dashboard.overviewDigest}
        focusAreas={dashboard.overviewFocusAreas}
        spotlights={dashboard.overviewSpotlights}
        sources={dashboard.sourceDimensions}
      />

      <section className="hero-operations-grid">
        {integratedAnalysis ? <DimensionAnalysisPanel analysis={integratedAnalysis} /> : null}
        <ShareReadyPanel />
      </section>

      <section id="insight-hub" className="dimension-panel-stack">
        <div className="section-banner">
          <div>
            <p className="panel-kicker">Insight Hub</p>
            <h2>脱敏后仍然保留分维度判断与回到总览的逻辑</h2>
            <p className="panel-description">
              这部分用来讲产品方法，而不是讲某个人的真实数据。展示重点是“先拆开看，再整合判断”。
            </p>
          </div>
        </div>

        {dimensionPanels.map((analysis) => (
          <DimensionAnalysisPanel key={analysis.key} analysis={analysis} />
        ))}
      </section>

      <section id="visual-lab" className="visual-lab-section">
        <div className="section-banner">
          <div>
            <p className="panel-kicker">Visual Lab</p>
            <h2>用 mock 趋势图保留产品表达与交互节奏</h2>
            <p className="panel-description">
              趋势关系、起伏节奏和面板分工都保留，但具体数值与日期已重写，便于直接用于内部讲解。
            </p>
          </div>
        </div>

        <div className="visual-lab-grid">
          <AnnualExamPanel exam={dashboard.annualExam} />
          <TrendPanel chart={dashboard.charts.lipid} />
          <TrendPanel chart={dashboard.charts.bodyComposition} />
          <TrendPanel chart={dashboard.charts.recovery} />
          <TrendPanel chart={dashboard.charts.activity} />
          <GeneticFindingsPanel findings={dashboard.geneticFindings} />
        </div>
      </section>

      <section id="brief-report" className="brief-report-grid">
        <section className="panel-card narrative-panel">
          <div className="panel-head">
            <div>
              <p className="panel-kicker">Latest AI Brief</p>
              <h2>脱敏综合摘要</h2>
              <p className="panel-description">{dashboard.latestNarrative.output.headline}</p>
            </div>
          </div>

          <div className="summary-grid">
            <article>
              <h3>本期变化</h3>
              {renderNarrativeList(dashboard.latestNarrative.output.most_important_changes)}
            </article>
            <article>
              <h3>优先动作</h3>
              {renderNarrativeList(dashboard.latestNarrative.output.priority_actions)}
            </article>
            <article>
              <h3>可能原因</h3>
              {renderNarrativeList(dashboard.latestNarrative.output.possible_reasons)}
            </article>
            <article>
              <h3>继续观察</h3>
              {renderNarrativeList(dashboard.latestNarrative.output.continue_observing)}
            </article>
          </div>

          <p className="summary-disclaimer">{dashboard.latestNarrative.output.disclaimer}</p>
        </section>

        <section className="panel-card">
          <div className="panel-head">
            <div>
              <p className="panel-kicker">Report Samples</p>
              <h2>分享版报告快照</h2>
              <p className="panel-description">
                这里保留报告卡片结构，但不再跳转到真实详情，只用于讲解连续追踪与阶段性总结能力。
              </p>
            </div>
            <span className="mini-pill">仅展示样例</span>
          </div>

          <div className="stack-list">
            {dashboard.latestReports.map((report) => (
              <article key={report.id} className="report-card">
                <div className="report-card-head">
                  <div>
                    <p className="report-type">{report.reportType === "weekly" ? "周报" : "月报"}</p>
                    <h3>{report.title}</h3>
                  </div>
                  <span className="mini-pill">脱敏快照</span>
                </div>
                <p className="report-headline">{report.summary.output.headline}</p>
                <ul className="analysis-list">
                  {report.summary.output.priority_actions.slice(0, 2).map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
                <p className="report-period">
                  周期 {report.periodStart} 至 {report.periodEnd}
                </p>
              </article>
            ))}
          </div>
        </section>
      </section>
    </main>
  );
}
