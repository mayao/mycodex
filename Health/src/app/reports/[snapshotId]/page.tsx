import Link from "next/link";
import { notFound } from "next/navigation";

import { ReportDetail } from "../../../components/report-detail";
import { SiteHeader } from "../../../components/site-header";
import { getReportSnapshotDetail } from "../../../server/services/report-service";

export const dynamic = "force-dynamic";

export default async function ReportDetailPage({
  params
}: {
  params: Promise<{ snapshotId: string }>;
}) {
  const { snapshotId } = await params;
  const report = await getReportSnapshotDetail(decodeURIComponent(snapshotId));

  if (!report) {
    notFound();
  }

  return (
    <main className="app-shell">
      <SiteHeader generatedAt={report.createdAt} />
      <div className="back-link-row">
        <Link href="/reports" className="report-link">
          返回报告列表
        </Link>
      </div>
      <ReportDetail report={report} />
    </main>
  );
}
