import Link from "next/link";

interface SiteHeaderProps {
  generatedAt?: string;
}

const formatter = new Intl.DateTimeFormat("zh-CN", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit"
});

export function SiteHeader({ generatedAt }: SiteHeaderProps) {
  return (
    <header className="site-header">
      <div>
        <p className="site-kicker">Personal Health Ops</p>
        <h1 className="site-title">健康经营驾驶舱</h1>
        <p className="site-subtitle">把年度体检、连续指标和基因背景压缩成一张更适合日常决策的首页。</p>
      </div>

      <div className="site-header-meta">
        <nav className="site-nav" aria-label="主导航">
          <Link href="/">首页</Link>
          <Link href="/reports">周报 / 月报</Link>
        </nav>
        {generatedAt ? (
          <p className="site-timestamp">更新于 {formatter.format(new Date(generatedAt))}</p>
        ) : null}
      </div>
    </header>
  );
}
