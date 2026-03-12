import { DataUpdatePanel } from "../../components/data-update-panel";
import { SiteHeader } from "../../components/site-header";
import { getHealthHomePageData } from "../../server/services/health-home-service";

export const dynamic = "force-dynamic";

export default async function DataPage() {
  const dashboard = await getHealthHomePageData();

  return (
    <main className="app-shell">
      <SiteHeader generatedAt={dashboard.generatedAt} />

      <section className="hero-banner">
        <div className="hero-copy">
          <p className="panel-kicker">Data</p>
          <h2>上传文件或同步 Apple 健康，更新当前健康档案。</h2>
          <p>这里集中处理数据导入、状态查看和最近记录。</p>
        </div>
      </section>

      <DataUpdatePanel options={dashboard.importOptions} sources={dashboard.sourceDimensions} />
    </main>
  );
}
