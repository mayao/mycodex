"use client";

import { useState } from "react";

import type { HealthTrendChartModel, TrendRangeKey } from "../server/domain/health-hub";
import { TrendChart } from "./trend-chart";

const rangeOptions: Array<{ key: TrendRangeKey; label: string; days?: number }> = [
  { key: "30d", label: "最近 30 天", days: 30 },
  { key: "90d", label: "最近 90 天", days: 90 },
  { key: "1y", label: "最近 1 年", days: 365 },
  { key: "all", label: "全部" }
];

function filterData(
  data: HealthTrendChartModel["data"],
  range: TrendRangeKey
): HealthTrendChartModel["data"] {
  const option = rangeOptions.find((item) => item.key === range);

  if (!option?.days || data.length === 0) {
    return data;
  }

  const latestDate = new Date(`${data.at(-1)?.date ?? data[0]?.date}T00:00:00+08:00`).getTime();
  const start = latestDate - option.days * 24 * 60 * 60 * 1000;

  return data.filter((item) => {
    const ts = new Date(`${item.date}T00:00:00+08:00`).getTime();
    return ts >= start;
  });
}

export function TrendPanel({ chart }: { chart: HealthTrendChartModel }) {
  const [range, setRange] = useState<TrendRangeKey>(chart.defaultRange);
  const filtered = filterData(chart.data, range);
  const activeRangeLabel =
    rangeOptions.find((option) => option.key === range)?.label ?? chart.defaultRange;

  return (
    <section className="panel-card">
      <div className="panel-head">
        <div>
          <p className="panel-kicker">Trend</p>
          <h2>{chart.title}</h2>
          <p className="panel-description">{chart.description}</p>
          <div className="trend-meta">
            <span>{chart.lines.length} 条指标</span>
            <span>{filtered.length} 个采样点</span>
            <span>{activeRangeLabel}</span>
          </div>
        </div>
        <div className="range-switch" role="tablist" aria-label={`${chart.title} 时间范围`}>
          {rangeOptions.map((option) => (
            <button
              key={option.key}
              type="button"
              className={option.key === range ? "range-pill is-active" : "range-pill"}
              onClick={() => setRange(option.key)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      {filtered.length > 0 ? (
        <TrendChart data={filtered} lines={chart.lines} />
      ) : (
        <div className="empty-chart">当前时间范围内没有可展示的数据。</div>
      )}
    </section>
  );
}
