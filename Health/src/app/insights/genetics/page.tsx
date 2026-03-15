"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

interface GeneticsInsight {
  generatedAt: string;
  sections: {
    overview: string;
    highRiskPoints: string[];
    healthCorrelations: string[];
    lifestyleAdvice: string[];
    longTermMonitoring: string[];
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

export default function GeneticsInsightPage() {
  const [insight, setInsight] = useState<GeneticsInsight | null>(null);
  const [loading, setLoading] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/insights/genetics")
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
          <h1>基因报告 AI 洞察</h1>
          <p>基因背景与你当前健康状态的深度关联分析</p>
        </div>
      </header>

      <div className="insight-body">
        {loading && (
          <div className="insight-loading">
            <div className="insight-loading-spinner" />
            <p>正在解读基因报告，请稍候…</p>
          </div>
        )}

        {!loading && unavailable && (
          <div className="insight-unavailable">
            <p>你还没有上传基因检测数据。</p>
            <Link href="/data" className="insight-upload-link">
              前往上传基因数据 →
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
              <p className="insight-kicker">基因组合解读</p>
              <p className="insight-overview-text">{insight.sections.overview}</p>
              <p className="insight-meta">
                分析时间 {new Date(insight.generatedAt).toLocaleDateString("zh-CN")}
              </p>
            </div>

            <InsightSection
              title="高风险关注点"
              items={insight.sections.highRiskPoints}
              tone="urgent"
              emptyLabel="暂无高风险基因位点需要特别关注。"
            />

            <InsightSection
              title="与现有健康状况的关联"
              items={insight.sections.healthCorrelations}
              tone="attention"
              emptyLabel="当前基因项关联的健康指标均在正常范围内。"
            />

            <InsightSection
              title="生活方式建议"
              items={insight.sections.lifestyleAdvice}
              tone="neutral"
            />

            <InsightSection
              title="长期监测建议"
              items={insight.sections.longTermMonitoring}
              tone="positive"
            />

            <p className="insight-disclaimer">{insight.disclaimer}</p>
          </>
        )}
      </div>
    </main>
  );
}
