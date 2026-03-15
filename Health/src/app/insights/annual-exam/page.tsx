"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

interface AnnualExamInsight {
  generatedAt: string;
  examTitle: string;
  sections: {
    overview: string;
    attentionPoints: string[];
    improvements: string[];
    urgentIssues: string[];
    positiveSignals: string[];
  };
  disclaimer: string;
  provider: string;
  model: string;
}

interface InsightSectionProps {
  title: string;
  items: string[];
  tone: "urgent" | "attention" | "positive" | "neutral";
  emptyLabel?: string;
}

function InsightSection({ title, items, tone, emptyLabel }: InsightSectionProps) {
  if (items.length === 0 && !emptyLabel) return null;

  return (
    <section className={`insight-section insight-section-${tone}`}>
      <h3 className="insight-section-title">{title}</h3>
      {items.length === 0 ? (
        <p className="insight-empty-note">{emptyLabel}</p>
      ) : (
        <ul className="insight-list">
          {items.map((item, index) => (
            <li key={index}>{item}</li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default function AnnualExamInsightPage() {
  const [insight, setInsight] = useState<AnnualExamInsight | null>(null);
  const [loading, setLoading] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/insights/annual-exam")
      .then((res) => res.json())
      .then((payload) => {
        if (!payload.available) {
          setUnavailable(true);
        } else {
          setInsight(payload.insight);
        }
      })
      .catch(() => {
        setError("洞察分析加载失败，请稍后重试。");
      })
      .finally(() => {
        setLoading(false);
      });
  }, []);

  return (
    <main className="app-shell insight-shell">
      <header className="insight-header">
        <Link href="/" className="insight-back" aria-label="返回首页">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="15 18 9 12 15 6" />
          </svg>
        </Link>
        <div>
          <h1>体检报告 AI 洞察</h1>
          <p>基于你的体检数据生成的个性化分析</p>
        </div>
      </header>

      <div className="insight-body">
        {loading && (
          <div className="insight-loading">
            <div className="insight-loading-spinner" />
            <p>正在分析体检报告，请稍候…</p>
          </div>
        )}

        {!loading && unavailable && (
          <div className="insight-unavailable">
            <p>你还没有上传体检报告。</p>
            <Link href="/data" className="insight-upload-link">
              前往上传体检数据 →
            </Link>
          </div>
        )}

        {!loading && error && (
          <div className="insight-error">
            <p>{error}</p>
          </div>
        )}

        {!loading && insight && (
          <>
            <div className="insight-overview-card">
              <p className="insight-kicker">综合评估</p>
              <p className="insight-overview-text">{insight.sections.overview}</p>
              <p className="insight-meta">
                {insight.examTitle} · 分析时间 {new Date(insight.generatedAt).toLocaleDateString("zh-CN")}
              </p>
            </div>

            {insight.sections.urgentIssues.length > 0 && (
              <InsightSection
                title="建议就医 / 复查"
                items={insight.sections.urgentIssues}
                tone="urgent"
              />
            )}

            <InsightSection
              title="需要注意的点"
              items={insight.sections.attentionPoints}
              tone="attention"
              emptyLabel="暂无需要特别注意的异常指标。"
            />

            <InsightSection
              title="改善建议"
              items={insight.sections.improvements}
              tone="neutral"
              emptyLabel="继续保持当前健康生活方式。"
            />

            <InsightSection
              title="积极信号"
              items={insight.sections.positiveSignals}
              tone="positive"
            />

            <p className="insight-disclaimer">{insight.disclaimer}</p>
          </>
        )}
      </div>
    </main>
  );
}
