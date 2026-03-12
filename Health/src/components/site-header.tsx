import Link from "next/link";

interface SiteHeaderProps {
  generatedAt?: string;
  kicker?: string;
  title?: string;
  subtitle?: string;
  badge?: string;
  navLinks?: { href: string; label: string }[];
}

const formatter = new Intl.DateTimeFormat("zh-CN", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit"
});

export function SiteHeader({ generatedAt, kicker, title, subtitle, badge, navLinks }: SiteHeaderProps) {
  const defaultNavLinks = [
    { href: "/", label: "首页" },
    { href: "/data", label: "数据" },
    { href: "/reports", label: "周报 / 月报" },
  ];
  const links = navLinks ?? defaultNavLinks;

  return (
    <header className="site-header">
      <div>
        <p className="site-kicker">{kicker ?? "Personal Health Ops"}</p>
        <h1 className="site-title">{title ?? "健康经营驾驶舱"}{badge ? <span className="mini-pill" style={{ marginLeft: 8 }}>{badge}</span> : null}</h1>
        <p className="site-subtitle">{subtitle ?? "把年度体检、连续指标和基因背景压缩成一张更适合日常决策的首页。"}</p>
      </div>

      <div className="site-header-meta">
        <nav className="site-nav" aria-label="主导航">
          {links.map((link) => (
            <Link key={link.href} href={link.href}>{link.label}</Link>
          ))}
          {!navLinks ? (
            <Link href="/ai" className="ai-chat-icon-link" aria-label="AI 对话" title="AI 健康助手">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                <circle cx="9" cy="10" r="0.5" fill="currentColor" />
                <circle cx="12" cy="10" r="0.5" fill="currentColor" />
                <circle cx="15" cy="10" r="0.5" fill="currentColor" />
              </svg>
            </Link>
          ) : null}
        </nav>
        {generatedAt ? (
          <p className="site-timestamp">更新于 {formatter.format(new Date(generatedAt))}</p>
        ) : null}
      </div>
    </header>
  );
}
