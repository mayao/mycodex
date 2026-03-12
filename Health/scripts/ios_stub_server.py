#!/usr/bin/env python3

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


TZ = timezone(timedelta(hours=8))
NOW = datetime(2026, 3, 11, 11, 0, tzinfo=TZ)


def iso(dt: datetime) -> str:
    return dt.isoformat()


def summary_output(period_kind: str, headline: str, priority_actions: list[str]) -> dict:
    return {
        "period_kind": period_kind,
        "headline": headline,
        "most_important_changes": [
            "LDL-C 与体脂率继续回落，说明近期饮食与训练组合仍然有效。",
            "最近 10 天睡眠恢复略有起伏，恢复节奏是下一阶段更关键的变量。"
        ],
        "possible_reasons": [
            "运动分钟保持在中高位，训练频率没有断档。",
            "工作日晚睡让恢复曲线有轻微波动。"
        ],
        "priority_actions": priority_actions,
        "continue_observing": [
            "Lp(a) 仍按长期慢变量观察，不做短线判断。",
            "维持每周 4 次以上中等强度运动，持续记录体脂与睡眠。"
        ],
        "disclaimer": "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。"
    }


def summary_bundle(period_kind: str, headline: str, priority_actions: list[str]) -> dict:
    return {
        "provider": "mock",
        "model": "healthai-local-demo",
        "prompt": {
            "template_id": "healthai-cn-v1",
            "version": "2026-03-11",
            "system_prompt": "你是 HealthAI 的健康摘要引擎。",
            "user_prompt": "结合体脂、血脂、运动和睡眠数据输出结构化摘要。"
        },
        "output": summary_output(period_kind, headline, priority_actions)
    }


def metric_summary(
    metric_code: str,
    metric_name: str,
    category: str,
    unit: str,
    latest_value: float,
    abnormal_flag: str,
    trend_direction: str,
    sample_time: datetime,
    historical_mean: float | None = None,
    latest_vs_mean: float | None = None,
    latest_vs_mean_pct: float | None = None,
    month_over_month: float | None = None,
    year_over_year: float | None = None,
    reference_range: str | None = None
) -> dict:
    return {
        "metric_code": metric_code,
        "metric_name": metric_name,
        "category": category,
        "unit": unit,
        "sample_count": 8,
        "latest_value": latest_value,
        "latest_sample_time": iso(sample_time),
        "historical_mean": historical_mean,
        "latest_vs_mean": latest_vs_mean,
        "latest_vs_mean_pct": latest_vs_mean_pct,
        "trend_direction": trend_direction,
        "month_over_month": month_over_month,
        "year_over_year": year_over_year,
        "abnormal_flag": abnormal_flag,
        "reference_range": reference_range
    }


def structured_insight(
    insight_id: str,
    title: str,
    severity: str,
    summary: str,
    metric_code: str,
    metric_name: str,
    unit: str,
    latest_value: float,
    suggested_action: str
) -> dict:
    return {
        "id": insight_id,
        "kind": "trend",
        "title": title,
        "severity": severity,
        "evidence": {
            "summary": summary,
            "metrics": [
                {
                    "metric_code": metric_code,
                    "metric_name": metric_name,
                    "unit": unit,
                    "latest_value": latest_value,
                    "latest_sample_time": iso(NOW - timedelta(days=1)),
                    "sample_count": 8,
                    "historical_mean": latest_value + 0.8,
                    "latest_vs_mean": -0.8,
                    "latest_vs_mean_pct": -18.5,
                    "trend_direction": "down",
                    "month_over_month": -0.2,
                    "year_over_year": -0.9,
                    "abnormal_flag": "normal" if severity != "high" else "high",
                    "reference_range": None,
                    "related_record_ids": [f"sample-{insight_id}"]
                }
            ]
        },
        "possible_reason": "近期训练频率稳定且晚餐结构改善。",
        "suggested_action": suggested_action,
        "disclaimer": "用于健康管理提示，不替代临床判断。"
    }


def overview_card(metric_code: str, label: str, value: str, trend: str, status: str, abnormal_flag: str, meaning: str) -> dict:
    return {
        "metric_code": metric_code,
        "label": label,
        "value": value,
        "trend": trend,
        "status": status,
        "abnormal_flag": abnormal_flag,
        "meaning": meaning
    }


def trend_points(base_date: datetime, interval_days: int, values: list[dict[str, float]]) -> list[dict]:
    points = []
    for index, row in enumerate(values):
        item = {"date": (base_date + timedelta(days=index * interval_days)).date().isoformat()}
        item.update(row)
        points.append(item)
    return points


def build_report(report_id: str, report_type: str, title: str, start: datetime, end: datetime, headline: str) -> dict:
    metrics = [
        metric_summary("lipid.ldl_c", "LDL-C", "lipid", "mmol/L", 2.82, "normal", "down", end, 3.38, -0.56, -16.6, -0.18, -0.92, "<3.40 mmol/L"),
        metric_summary("body.body_fat_pct", "体脂率", "body", "%", 20.8, "normal", "down", end, 22.3, -1.5, -6.7, -0.6, -2.3, "10-20%"),
        metric_summary("activity.exercise_minutes", "训练分钟", "activity", "min", 56, "normal", "up", end, 44, 12, 27.2, 6, 8, None),
        metric_summary("sleep.asleep_minutes", "睡眠时长", "sleep", "min", 425, "normal", "up", end, 404, 21, 5.2, 10, 18, None)
    ]
    return {
        "id": report_id,
        "report_type": report_type,
        "period_start": start.date().isoformat(),
        "period_end": end.date().isoformat(),
        "created_at": iso(end + timedelta(hours=1)),
        "title": title,
        "summary": summary_bundle(
            "week" if report_type == "weekly" else "month",
            headline,
            ["继续维持每周 4 次训练。", "把入睡时间再提前 30 分钟。"]
        ),
        "structured_insights": {
            "generated_at": iso(end + timedelta(hours=1)),
            "user_id": "user-self",
            "metric_summaries": metrics,
            "insights": [
                structured_insight(
                    f"{report_id}-lipid",
                    "血脂主线继续改善",
                    "positive",
                    "LDL-C 和 ApoB 同步回落，近期干预仍在起效。",
                    "lipid.ldl_c",
                    "LDL-C",
                    "mmol/L",
                    2.82,
                    "维持当前饮食结构与力量训练节奏。"
                ),
                structured_insight(
                    f"{report_id}-sleep",
                    "恢复窗口仍可再拉长",
                    "medium",
                    "训练强度维持后，睡眠时长仍是决定恢复质量的主变量。",
                    "sleep.asleep_minutes",
                    "睡眠时长",
                    "min",
                    425,
                    "工作日尽量将入睡时间稳定在 23:30 前。"
                )
            ]
        }
    }


weekly_reports = [
    build_report("weekly-2026-03-10", "weekly", "周报 | 代谢与恢复联动", NOW - timedelta(days=7), NOW - timedelta(days=1), "本周的主线是血脂和体脂继续改善，但恢复节奏还可以再稳一些。"),
    build_report("weekly-2026-03-03", "weekly", "周报 | 训练执行度保持", NOW - timedelta(days=14), NOW - timedelta(days=8), "训练完成度稳定，体组成曲线继续向理想区间移动。")
]

monthly_reports = [
    build_report("monthly-2026-02", "monthly", "月报 | 二月整体健康画像", datetime(2026, 2, 1, tzinfo=TZ), datetime(2026, 2, 28, tzinfo=TZ), "二月的关键变化是 LDL-C、体脂率和睡眠恢复同时朝更好的方向移动。")
]

reports_by_id = {report["id"]: report for report in [*weekly_reports, *monthly_reports]}

dashboard_payload = {
    "generated_at": iso(NOW),
    "disclaimer": "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。",
    "overview_headline": "年度体检基线与近期专项复查显示整体在改善，当前主线是继续把减脂、血脂和恢复三条线拉齐。",
    "overview_narrative": "HealthAI 把年度体检、血脂专项、体脂秤、运动和睡眠数据放在同一张仪表盘里，弱化大段文字，优先展示曲线、数值和行动提示。",
    "overview_digest": {
        "headline": "整体趋势偏积极，恢复是下一阶段最值得优化的变量。",
        "summary": "血脂和体脂在下降，训练执行度稳定，睡眠恢复仍有提升空间。",
        "good_signals": [
            "LDL-C 已从年度体检的 3.62 mmol/L 回落到 2.82 mmol/L。",
            "体脂率连续 5 次记录缓慢下降。",
            "近两周训练分钟维持在日均 52 分钟附近。"
        ],
        "needs_attention": [
            "工作日晚睡导致睡眠恢复偶有波动。",
            "Lp(a) 仍需要作为慢变量长期观察。"
        ],
        "long_term_risks": [
            "如果恢复长期不足，训练收益可能被稀释。",
            "长期慢变量仍需靠稳定生活方式管理。"
        ],
        "action_plan": [
            "把固定入睡时间提前 30 分钟。",
            "维持当前饮食结构和训练频次。"
        ]
    },
    "overview_focus_areas": ["血脂回落", "体脂优化", "训练执行", "睡眠恢复", "长期背景"],
    "overview_spotlights": [
        {"label": "年度体检焦点", "value": "3 项需持续跟踪", "tone": "attention", "detail": "LDL-C、体脂率、Lp(a)"},
        {"label": "近期代谢状态", "value": "78.4kg / 20.8%", "tone": "positive", "detail": "体重与体脂同步回落"},
        {"label": "睡眠恢复", "value": "7.1 h", "tone": "neutral", "detail": "恢复质量较上月更平稳"},
        {"label": "基因解释层", "value": "4 条 finding / 3 维", "tone": "neutral", "detail": "长期背景已纳入解释"}
    ],
    "source_dimensions": [
        {"key": "annual_exam", "label": "年度体检", "latest_at": "2025-12-18", "status": "attention", "summary": "保留为长期基线。", "highlight": "3 项需持续跟踪"},
        {"key": "lipid", "label": "近期血脂专项", "latest_at": "2026-03-09", "status": "ready", "summary": "LDL-C 与 ApoB 同步回落。", "highlight": "LDL-C 2.82 mmol/L"},
        {"key": "body", "label": "体脂秤趋势", "latest_at": "2026-03-10", "status": "ready", "summary": "体重与体脂率同向改善。", "highlight": "体脂率 20.8%"},
        {"key": "activity", "label": "运动执行度", "latest_at": "2026-03-10", "status": "ready", "summary": "训练分钟维持中高位。", "highlight": "56 min"},
        {"key": "genetic", "label": "基因背景", "latest_at": "2026-02-05", "status": "background", "summary": "已纳入长期解释维度。", "highlight": "3 个维度"}
    ],
    "dimension_analyses": [
        {
            "key": "lipid_body",
            "kicker": "代谢主线",
            "title": "血脂与体脂在同步改善",
            "summary": "当前干预效果不仅体现在化验值，也体现在身体组成变化。",
            "good_signals": ["LDL-C 继续下降", "体脂率连续回落"],
            "needs_attention": ["恢复仍可更稳定"],
            "long_term_risks": ["Lp(a) 仍需长期观察"],
            "action_plan": ["保持饮食结构", "维持力量训练"],
            "metrics": [
                {"label": "LDL-C", "value": "2.82 mmol/L", "detail": "较年度体检 -0.80 mmol/L", "tone": "positive"},
                {"label": "体脂率", "value": "20.8 %", "detail": "近阶段继续下降", "tone": "positive"}
            ]
        },
        {
            "key": "activity_recovery",
            "kicker": "执行与恢复",
            "title": "训练保持良好，但恢复是放大收益的关键",
            "summary": "如果睡眠更稳定，训练收益和代谢改善会更扎实。",
            "good_signals": ["训练频率稳定"],
            "needs_attention": ["工作日晚睡"],
            "long_term_risks": ["恢复不足会拉低训练收益"],
            "action_plan": ["固定入睡时间", "避免晚间高刺激咖啡因"],
            "metrics": [
                {"label": "训练分钟", "value": "56 min", "detail": "近两周均值 52 min", "tone": "positive"},
                {"label": "睡眠", "value": "7.1 h", "detail": "近一周较上周更稳定", "tone": "neutral"}
            ]
        }
    ],
    "import_options": [
        {"key": "annual_exam", "title": "年度体检", "description": "导入体检结构化结果。", "formats": [".csv", ".xlsx"], "hints": ["支持体检指标字段映射", "可导入历年数据", "异常行会单独记录"]},
        {"key": "blood_test", "title": "血液专项", "description": "导入血脂、生化等专项结果。", "formats": [".csv", ".xlsx"], "hints": ["支持 LDL-C、ApoB、Lp(a)", "自动做单位换算", "支持批量导入"]},
        {"key": "body_scale", "title": "体脂秤", "description": "导入体重、体脂与 BMI 数据。", "formats": [".csv"], "hints": ["支持 Fitdays 导出", "自动识别时间列", "连续趋势效果更好"]},
        {"key": "activity", "title": "运动", "description": "导入运动分钟、消耗和站立时长。", "formats": [".csv"], "hints": ["支持 Apple Health 导出", "训练分钟优先", "可合并日级样本"]}
    ],
    "overview_cards": [
        overview_card("lipid.ldl_c", "LDL-C", "2.82 mmol/L", "较历史均值 -0.56 mmol/L", "improving", "normal", "血脂关键指标"),
        overview_card("lipid.total_cholesterol", "TC", "4.48 mmol/L", "近阶段继续下降", "improving", "normal", "总胆固醇"),
        overview_card("body.body_fat_pct", "体脂率", "20.8 %", "较历史均值 -1.5%", "improving", "normal", "减脂质量"),
        overview_card("activity.exercise_minutes", "训练分钟", "56 min", "近阶段继续上升", "stable", "normal", "运动执行度"),
        overview_card("sleep.asleep_minutes", "睡眠", "425 min", "较历史均值 +21 min", "stable", "normal", "恢复质量")
    ],
    "annual_exam": {
        "latest_title": "2025 年年度体检",
        "latest_recorded_at": "2025-12-18",
        "previous_title": "2024 年年度体检",
        "metrics": [
            {"metric_code": "body.weight", "label": "体重", "short_label": "体重", "unit": "kg", "latest_value": 79.8, "previous_value": 82.1, "delta": -2.3, "abnormal_flag": "normal", "reference_range": "60.6-82.0", "meaning": "总体体重", "practical_advice": "维持当前减脂节奏"},
            {"metric_code": "body.bmi", "label": "BMI", "short_label": "BMI", "unit": "kg/m2", "latest_value": 24.6, "previous_value": 25.4, "delta": -0.8, "abnormal_flag": "borderline", "reference_range": "18.5-24.9", "meaning": "总体体型指标", "practical_advice": "继续观察体重与体脂联动"},
            {"metric_code": "body.body_fat_pct", "label": "体脂率", "short_label": "体脂", "unit": "%", "latest_value": 22.1, "previous_value": 24.2, "delta": -2.1, "abnormal_flag": "high", "reference_range": "10-20", "meaning": "身体成分质量", "practical_advice": "继续力量训练和高蛋白饮食"},
            {"metric_code": "lipid.ldl_c", "label": "LDL-C", "short_label": "LDL-C", "unit": "mmol/L", "latest_value": 3.62, "previous_value": 3.88, "delta": -0.26, "abnormal_flag": "high", "reference_range": "<3.40", "meaning": "代谢风险主指标", "practical_advice": "继续近期饮食和运动干预"}
        ],
        "abnormal_metric_labels": ["LDL-C", "体脂率", "BMI"],
        "improved_metric_labels": ["体重", "LDL-C", "体脂率"],
        "highlight_summary": "年度体检保留为长期基线，近期干预重点仍然是血脂与体脂。",
        "action_summary": "继续减脂、规律训练和睡眠优化。"
    },
    "genetic_findings": [
        {"id": "gf-1", "gene_symbol": "LPA", "trait_label": "Lp(a) 背景偏高", "dimension": "血脂", "risk_level": "medium", "evidence_level": "A", "summary": "属于慢变量背景，更适合长期管理。", "suggestion": "把注意力放在长期生活方式管理上。", "recorded_at": "2026-02-05", "linked_metric_label": "Lp(a)", "linked_metric_value": "47 mg/dL", "linked_metric_flag": "high", "plain_meaning": "短期很难大幅波动", "practical_advice": "持续记录并年度复查"},
        {"id": "gf-2", "gene_symbol": "CYP1A2", "trait_label": "咖啡因敏感", "dimension": "恢复", "risk_level": "low", "evidence_level": "B", "summary": "晚间咖啡因更容易影响睡眠。", "suggestion": "下午 3 点后减少咖啡因。", "recorded_at": "2026-02-05", "linked_metric_label": "睡眠时长", "linked_metric_value": "7.1 h", "linked_metric_flag": "normal", "plain_meaning": "恢复更容易受刺激物影响", "practical_advice": "工作日尽量提前停止含咖啡因饮品"},
        {"id": "gf-3", "gene_symbol": "ACTN3", "trait_label": "力量训练反应较好", "dimension": "运动", "risk_level": "low", "evidence_level": "B", "summary": "更适合保留规律力量训练。", "suggestion": "维持每周 2-3 次力量训练。", "recorded_at": "2026-02-05", "linked_metric_label": "训练分钟", "linked_metric_value": "56 min", "linked_metric_flag": "normal", "plain_meaning": "力量训练收益较好", "practical_advice": "不要只做纯有氧"}
    ],
    "key_reminders": [
        {"id": "rem-1", "title": "继续维持减脂质量", "severity": "positive", "summary": "体脂率和体重都在往理想方向移动。", "suggested_action": "保持当前饮食与训练结构。", "indicator_meaning": "近期方向正确", "practical_advice": "继续记录每周体脂变化"},
        {"id": "rem-2", "title": "睡眠恢复还可再稳一点", "severity": "medium", "summary": "最近工作日晚睡让恢复曲线有波动。", "suggested_action": "把入睡时间前移 30 分钟。", "indicator_meaning": "恢复质量影响训练收益", "practical_advice": "下午晚些时候减少咖啡因"},
        {"id": "rem-3", "title": "Lp(a) 维持长期观察", "severity": "low", "summary": "它更像慢变量，不适合短期焦虑解读。", "suggested_action": "按季度或年度复查即可。", "indicator_meaning": "长期背景项", "practical_advice": "继续关注整体生活方式"},
        {"id": "rem-4", "title": "训练执行度值得保留", "severity": "positive", "summary": "近两周训练分钟保持稳定。", "suggested_action": "继续维持每周 4 次训练。", "indicator_meaning": "执行度稳定", "practical_advice": "适度增加力量训练比重"}
    ],
    "watch_items": [],
    "latest_narrative": summary_bundle(
        "day",
        "代谢主线继续改善，当前最值得优化的是恢复节奏。",
        ["工作日晚间尽量提前半小时入睡。", "保持当前减脂与力量训练组合。"]
    ),
    "charts": {
        "lipid": {
            "title": "血脂趋势图",
            "description": "把 LDL-C、TG、HDL-C 和 Lp(a) 放在同一视角里看。",
            "default_range": "1y",
            "data": trend_points(datetime(2025, 10, 1, tzinfo=TZ), 30, [
                {"ldl": 3.70, "tg": 1.56, "hdl": 1.03, "tc": 5.62, "lpa": 52},
                {"ldl": 3.42, "tg": 1.44, "hdl": 1.08, "tc": 5.21, "lpa": 50},
                {"ldl": 3.20, "tg": 1.31, "hdl": 1.12, "tc": 4.92, "lpa": 49},
                {"ldl": 3.04, "tg": 1.22, "hdl": 1.16, "tc": 4.76, "lpa": 48},
                {"ldl": 2.90, "tg": 1.15, "hdl": 1.19, "tc": 4.58, "lpa": 47},
                {"ldl": 2.82, "tg": 1.09, "hdl": 1.21, "tc": 4.48, "lpa": 47}
            ]),
            "lines": [
                {"key": "ldl", "label": "LDL-C", "color": "#0f766e", "unit": "mmol/L", "y_axis_id": "left"},
                {"key": "tg", "label": "TG", "color": "#d97706", "unit": "mmol/L", "y_axis_id": "left"},
                {"key": "hdl", "label": "HDL-C", "color": "#2563eb", "unit": "mmol/L", "y_axis_id": "left"},
                {"key": "tc", "label": "TC", "color": "#9f1239", "unit": "mmol/L", "y_axis_id": "left"},
                {"key": "lpa", "label": "Lp(a)", "color": "#5b21b6", "unit": "mg/dL", "y_axis_id": "right"}
            ]
        },
        "body_composition": {
            "title": "体重 / 体脂趋势图",
            "description": "以减脂质量为主，不只盯体重。",
            "default_range": "1y",
            "data": trend_points(datetime(2025, 10, 1, tzinfo=TZ), 30, [
                {"weight": 81.2, "bodyFat": 23.6, "bmi": 25.1},
                {"weight": 80.4, "bodyFat": 22.9, "bmi": 24.8},
                {"weight": 79.8, "bodyFat": 22.3, "bmi": 24.6},
                {"weight": 79.1, "bodyFat": 21.7, "bmi": 24.4},
                {"weight": 78.7, "bodyFat": 21.2, "bmi": 24.2},
                {"weight": 78.4, "bodyFat": 20.8, "bmi": 24.1}
            ]),
            "lines": [
                {"key": "weight", "label": "体重", "color": "#0f766e", "unit": "kg", "y_axis_id": "left"},
                {"key": "bodyFat", "label": "体脂率", "color": "#be123c", "unit": "%", "y_axis_id": "right"},
                {"key": "bmi", "label": "BMI", "color": "#0f4c81", "unit": "kg/m2", "y_axis_id": "right"}
            ]
        },
        "activity": {
            "title": "运动执行图",
            "description": "训练分钟和活动能量一起看。",
            "default_range": "90d",
            "data": trend_points(datetime(2026, 3, 1, tzinfo=TZ), 1, [
                {"exerciseMinutes": 42, "activeKcal": 510},
                {"exerciseMinutes": 48, "activeKcal": 560},
                {"exerciseMinutes": 54, "activeKcal": 620},
                {"exerciseMinutes": 46, "activeKcal": 530},
                {"exerciseMinutes": 58, "activeKcal": 650},
                {"exerciseMinutes": 64, "activeKcal": 720},
                {"exerciseMinutes": 52, "activeKcal": 605},
                {"exerciseMinutes": 50, "activeKcal": 590},
                {"exerciseMinutes": 56, "activeKcal": 680},
                {"exerciseMinutes": 61, "activeKcal": 705}
            ]),
            "lines": [
                {"key": "exerciseMinutes", "label": "训练分钟", "color": "#0f766e", "unit": "min", "y_axis_id": "left"},
                {"key": "activeKcal", "label": "活动能量", "color": "#c2410c", "unit": "kcal", "y_axis_id": "right"}
            ]
        },
        "recovery": {
            "title": "睡眠 / 恢复图",
            "description": "用睡眠和训练一起解释恢复质量。",
            "default_range": "90d",
            "data": trend_points(datetime(2026, 3, 1, tzinfo=TZ), 1, [
                {"sleepMinutes": 398, "exerciseMinutes": 42},
                {"sleepMinutes": 412, "exerciseMinutes": 48},
                {"sleepMinutes": 435, "exerciseMinutes": 54},
                {"sleepMinutes": 428, "exerciseMinutes": 46},
                {"sleepMinutes": 405, "exerciseMinutes": 58},
                {"sleepMinutes": 441, "exerciseMinutes": 64},
                {"sleepMinutes": 432, "exerciseMinutes": 52},
                {"sleepMinutes": 418, "exerciseMinutes": 50},
                {"sleepMinutes": 436, "exerciseMinutes": 56},
                {"sleepMinutes": 425, "exerciseMinutes": 61}
            ]),
            "lines": [
                {"key": "sleepMinutes", "label": "睡眠时间", "color": "#1d4ed8", "unit": "min", "y_axis_id": "left"},
                {"key": "exerciseMinutes", "label": "训练分钟", "color": "#0f766e", "unit": "min", "y_axis_id": "right"}
            ]
        }
    },
    "latest_reports": weekly_reports[:1] + monthly_reports[:1]
}


reports_index_payload = {
    "generated_at": iso(NOW),
    "weekly_reports": weekly_reports,
    "monthly_reports": monthly_reports
}


@dataclass
class JSONResponse:
    status: int
    body: dict


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        response = self.route("GET")
        self.respond(response)

    def do_POST(self) -> None:
        _ = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        response = self.route("POST")
        self.respond(response)

    def route(self, method: str) -> JSONResponse:
        path = urlparse(self.path).path

        if method == "GET" and path == "/api/dashboard":
            return JSONResponse(200, dashboard_payload)

        if method == "GET" and path == "/api/reports":
            return JSONResponse(200, reports_index_payload)

        if method == "GET" and path.startswith("/api/reports/"):
            report_id = path.rsplit("/", 1)[-1]
            report = reports_by_id.get(report_id)
            if report:
                return JSONResponse(200, report)
            return JSONResponse(404, {"error": {"id": "not_found", "message": "报告不存在。"}})

        if method == "POST" and path == "/api/privacy/export":
            return JSONResponse(501, {
                "status": "placeholder",
                "action": "export",
                "enabled": False,
                "request": {"scope": "all", "format": "json", "include_audit_logs": False},
                "requires_explicit_confirmation": False,
                "available_data": {"health_records": 186, "reports": 3, "imports": 4},
                "next_step": "隐私导出仍是占位接口，当前演示版未接真实导出流程。"
            })

        if method == "POST" and path == "/api/privacy/delete":
            return JSONResponse(501, {
                "status": "placeholder",
                "action": "delete",
                "enabled": False,
                "request": {"scope": "all", "import_task_id": None, "confirm": False},
                "requires_explicit_confirmation": True,
                "available_data": {"health_records": 186, "reports": 3, "imports": 4},
                "next_step": "隐私删除仍是占位接口，当前演示版未接真实删除流程。"
            })

        if method == "POST" and path == "/api/imports":
            return JSONResponse(200, {
                "result": {
                    "import_task_id": "demo-import-20260311",
                    "importer_key": "body_scale",
                    "file_path": "/tmp/demo.csv",
                    "task_status": "completed",
                    "total_records": 18,
                    "success_records": 18,
                    "failed_records": 0,
                    "log_summary": [],
                    "warnings": []
                }
            })

        return JSONResponse(404, {"error": {"id": "not_found", "message": "接口不存在。"}})

    def respond(self, response: JSONResponse) -> None:
        encoded = json.dumps(response.body, ensure_ascii=False).encode("utf-8")
        self.send_response(response.status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args) -> None:
        print(f"[ios-stub] {self.address_string()} - {format % args}")


def main() -> None:
    host = "0.0.0.0"
    port = 3000
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"HealthAI iOS stub server running on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
