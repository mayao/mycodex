"use client";

import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from "recharts";

import type { TrendPoint } from "../server/domain/types";

interface TrendLine {
  key: string;
  label: string;
  color: string;
  unit: string;
  yAxisId?: "left" | "right";
}

interface TrendChartProps {
  data: TrendPoint[];
  lines: TrendLine[];
}

const dateFormatter = new Intl.DateTimeFormat("zh-CN", {
  month: "numeric",
  day: "numeric"
});

export function TrendChart({ data, lines }: TrendChartProps) {
  const configMap = new Map(
    lines.flatMap((line) => [
      [line.key, line] as const,
      [line.label, line] as const
    ])
  );
  const hasRightAxis = lines.some((line) => line.yAxisId === "right");

  return (
    <div className="chart-shell">
      <ResponsiveContainer width="100%" height={320}>
        <LineChart data={data} margin={{ top: 8, right: 20, left: 0, bottom: 0 }}>
          <CartesianGrid stroke="rgba(16, 42, 67, 0.08)" strokeDasharray="4 4" />
          <XAxis
            dataKey="date"
            tickLine={false}
            axisLine={false}
            tickFormatter={(value: string) =>
              dateFormatter.format(new Date(`${value}T00:00:00+08:00`))
            }
          />
          <YAxis yAxisId="left" tickLine={false} axisLine={false} />
          {hasRightAxis ? (
            <YAxis
              yAxisId="right"
              orientation="right"
              tickLine={false}
              axisLine={false}
            />
          ) : null}
          <Tooltip
            contentStyle={{
              background: "rgba(255,255,255,0.95)",
              border: "1px solid rgba(16, 42, 67, 0.08)",
              borderRadius: 16
            }}
            labelFormatter={(value: string) =>
              dateFormatter.format(new Date(`${value}T00:00:00+08:00`))
            }
            formatter={(value, name) => {
              const config = configMap.get(name as string);
              return [`${value} ${config?.unit ?? ""}`, config?.label ?? name];
            }}
          />
          <Legend />
          {lines.map((line) => (
            <Line
              key={line.key}
              name={line.label}
              type="monotone"
              dataKey={line.key}
              stroke={line.color}
              strokeWidth={3}
              dot={{ r: 4, strokeWidth: 2, fill: "#ffffff" }}
              activeDot={{ r: 6 }}
              yAxisId={line.yAxisId ?? "left"}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
