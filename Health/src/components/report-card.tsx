import Link from "next/link";

import type { HealthReportSnapshotRecord } from "../server/domain/health-hub";

export function ReportCard({ report }: { report: HealthReportSnapshotRecord }) {
  return (
    <article className="report-card">
      <div className="report-card-head">
        <div>
          <p className="report-type">{report.reportType === "weekly" ? "周报" : "月报"}</p>
          <h3>{report.title}</h3>
        </div>
        <Link href={`/reports/${encodeURIComponent(report.id)}`} className="report-link">
          查看详情
        </Link>
      </div>
      <p className="report-headline">{report.summary.output.headline}</p>
      <ul className="report-points">
        {report.summary.output.priority_actions.slice(0, 2).map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
      <p className="report-period">
        周期 {report.periodStart} 至 {report.periodEnd}
      </p>
    </article>
  );
}
