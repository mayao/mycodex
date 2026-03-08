import Link from "next/link";

import { AnnualExamPanel } from "../components/annual-exam-panel";
import { GeneticFindingsPanel } from "../components/genetic-findings-panel";
import { HeroSummaryPanel } from "../components/hero-summary-panel";
import { OverviewSpotlightGrid } from "../components/overview-spotlight-grid";
import { SiteHeader } from "../components/site-header";
import { SourceDimensionStrip } from "../components/source-dimension-strip";
import { SummaryCard } from "../components/summary-card";
import { TrendPanel } from "../components/trend-panel";
import { getHealthHomePageData } from "../server/services/health-home-service";

export const dynamic = "force-dynamic";

function severityLabel(severity: "high" | "medium" | "low" | "positive"): string {
  if (severity === "high") {
    return "高优先";
  }

  if (severity === "medium") {
    return "持续关注";
  }

  if (severity === "positive") {
    return "积极变化";
  }

  return "继续观察";
}

export default async function HomePage() {
  const dashboard = await getHealthHomePageData();

  return (
    <main className="app-shell app-shell-pro">
      <SiteHeader generatedAt={dashboard.generatedAt} />

      <section className="hero-banner hero-banner-upgraded">
        <div className="hero-copy">
          <p className="panel-kicker">Health Overview</p>
          <h2>{dashboard.overviewHeadline}</h2>
          <p className="hero-narrative">{dashboard.overviewNarrative}</p>
          <div className="focus-chip-row">
            {dashboard.overviewFocusAreas.map((item) => (
              <span key={item} className="focus-chip">
                {item}
              </span>
            ))}
          </div>
          <OverviewSpotlightGrid items={dashboard.overviewSpotlights} />
        </div>

        <HeroSummaryPanel
          summary={dashboard.latestNarrative}
          reminders={dashboard.keyReminders}
          watchItems={dashboard.watchItems}
          geneticFindings={dashboard.geneticFindings}
          latestReports={dashboard.latestReports}
        />
      </section>

      <SourceDimensionStrip items={dashboard.sourceDimensions} />

      <section className="overview-grid overview-grid-expanded">
        {dashboard.overviewCards.map((card) => (
          <article
            key={card.metric_code}
            className={`overview-card status-${card.status} flag-${card.abnormal_flag}`}
          >
            <div className="overview-head">
              <p>{card.label}</p>
              <span className="mini-pill">{card.abnormal_flag}</span>
            </div>
            <h3>{card.value}</h3>
            <p>{card.trend}</p>
          </article>
        ))}
      </section>

      <section className="document-grid">
        <AnnualExamPanel exam={dashboard.annualExam} />
        <GeneticFindingsPanel findings={dashboard.geneticFindings} />
      </section>

      <section className="content-grid content-grid-wide">
        <section className="panel-card">
          <div className="panel-head">
            <div>
              <p className="panel-kicker">Alerts</p>
              <h2>本期关键提醒</h2>
              <p className="panel-description">
                这里不仅包含近期血液、体脂和运动变化，也会纳入年度体检和基因背景的长期维度。
              </p>
            </div>
          </div>
          <div className="stack-list">
            {dashboard.keyReminders.map((item) => (
              <article key={item.id} className={`reminder-card severity-${item.severity}`}>
                <div className="reminder-head">
                  <h3>{item.title}</h3>
                  <span className="mini-pill">{severityLabel(item.severity)}</span>
                </div>
                <p>{item.summary}</p>
                <p className="reminder-action">建议：{item.suggested_action}</p>
              </article>
            ))}
          </div>
        </section>

        <SummaryCard
          eyebrow="LLM Insight"
          title="综合洞察拆解"
          summary={dashboard.latestNarrative}
          focusAreas={dashboard.overviewFocusAreas}
        />
      </section>

      <section className="chart-grid chart-grid-expanded">
        <TrendPanel chart={dashboard.charts.lipid} />
        <TrendPanel chart={dashboard.charts.bodyComposition} />
        <TrendPanel chart={dashboard.charts.activity} />
        <TrendPanel chart={dashboard.charts.recovery} />
      </section>

      <section className="content-grid content-grid-wide">
        <section className="panel-card">
          <div className="panel-head">
            <div>
              <p className="panel-kicker">Watchlist</p>
              <h2>待关注事项</h2>
              <p className="panel-description">把短期波动、年度基线和长期背景分开看，避免误读。</p>
            </div>
          </div>
          <div className="stack-list">
            {dashboard.watchItems.map((item) => (
              <article key={item.id} className={`reminder-card severity-${item.severity}`}>
                <div className="reminder-head">
                  <h3>{item.title}</h3>
                  <span className="mini-pill">{severityLabel(item.severity)}</span>
                </div>
                <p>{item.summary}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="panel-card">
          <div className="panel-head">
            <div>
              <p className="panel-kicker">Reports</p>
              <h2>最新报告快照</h2>
              <p className="panel-description">周报和月报会继续继承体检、专项血液和基因背景的综合视角。</p>
            </div>
            <Link href="/reports" className="report-link">
              查看全部报告
            </Link>
          </div>

          <div className="stack-list">
            {dashboard.latestReports.map((report) => (
              <article key={report.id} className="report-card">
                <div className="report-card-head">
                  <div>
                    <p className="report-type">{report.reportType === "weekly" ? "周报" : "月报"}</p>
                    <h3>{report.title}</h3>
                  </div>
                  <Link href={`/reports/${encodeURIComponent(report.id)}`} className="report-link">
                    打开
                  </Link>
                </div>
                <p className="report-headline">{report.summary.output.headline}</p>
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
