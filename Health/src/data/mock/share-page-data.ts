import type {
  HealthHomePageData,
  HealthReportSnapshotRecord,
  HealthSummaryGenerationResult,
  HealthSummaryPeriod,
  SummaryPeriodKind
} from "../../server/domain/health-hub";
import type { TrendPoint } from "../../server/domain/types";
import type { StructuredInsightsResult } from "../../server/insights/types";
import { NON_DIAGNOSTIC_DISCLAIMER } from "./seed-data";

const generatedAt = "2026-03-10T09:30:00+08:00";
const shareDisclaimer = `分享版说明：以下为脱敏与 mock 数据，仅用于内部演示。${NON_DIAGNOSTIC_DISCLAIMER}`;

function createTrendPoint(
  date: string,
  values: Record<string, number | string | undefined>
): TrendPoint {
  return { date, ...values };
}

function createSummaryPeriod(kind: SummaryPeriodKind, start: string, end: string): HealthSummaryPeriod {
  const label =
    kind === "day"
      ? `${end} 日摘要`
      : `${start} 至 ${end} ${kind === "week" ? "周报" : "月报"}`;

  return {
    kind,
    label,
    start,
    end,
    asOf: `${end}T21:00:00+08:00`
  };
}

function createStructuredInsightsResult(): StructuredInsightsResult {
  return {
    generated_at: generatedAt,
    user_id: "share-demo-user",
    metric_summaries: [],
    insights: []
  };
}

function createNarrativeSummary(params: {
  period: HealthSummaryPeriod;
  headline: string;
  mostImportantChanges: string[];
  possibleReasons: string[];
  priorityActions: string[];
  continueObserving: string[];
}): HealthSummaryGenerationResult {
  return {
    provider: "mock",
    model: "mock-share-health-v1",
    prompt: {
      templateId: "share-demo-summary",
      version: "share-v1",
      systemPrompt: "输出适合内部分享的脱敏健康摘要。",
      userPrompt: `基于脱敏样例数据生成 ${params.period.label}。`
    },
    output: {
      period_kind: params.period.kind,
      headline: params.headline,
      most_important_changes: params.mostImportantChanges,
      possible_reasons: params.possibleReasons,
      priority_actions: params.priorityActions,
      continue_observing: params.continueObserving,
      disclaimer: shareDisclaimer
    }
  };
}

function createReportRecord(params: {
  id: string;
  reportType: HealthReportSnapshotRecord["reportType"];
  start: string;
  end: string;
  title: string;
  headline: string;
  mostImportantChanges: string[];
  possibleReasons: string[];
  priorityActions: string[];
  continueObserving: string[];
}): HealthReportSnapshotRecord {
  const period = createSummaryPeriod(
    params.reportType === "weekly" ? "week" : "month",
    params.start,
    params.end
  );

  return {
    id: params.id,
    reportType: params.reportType,
    periodStart: params.start,
    periodEnd: params.end,
    createdAt: `${params.end}T21:00:00+08:00`,
    title: params.title,
    summary: createNarrativeSummary({
      period,
      headline: params.headline,
      mostImportantChanges: params.mostImportantChanges,
      possibleReasons: params.possibleReasons,
      priorityActions: params.priorityActions,
      continueObserving: params.continueObserving
    }),
    structuredInsights: createStructuredInsightsResult()
  };
}

const latestNarrative = createNarrativeSummary({
  period: createSummaryPeriod("day", "2026-03-10", "2026-03-10"),
  headline: "演示样例中，脂代谢趋势与行为执行同步改善，适合用于展示“多源数据整合后给出行动建议”的产品能力。",
  mostImportantChanges: [
    "年度体检样例与近 3 个月复查样例在 LDL-C、ApoB 上呈现一致回落趋势。",
    "体重和体脂率保持缓慢下降，同时周内运动分钟数维持在较稳定区间。",
    "恢复维度不再是主要拖累项，睡眠时长与静息心率表现出更平稳的节奏。"
  ],
  possibleReasons: [
    "饮食、运动和复查节奏被设计成彼此呼应，便于在分享时解释“行为变化如何映射到指标”。",
    "示例趋势刻意保留了小幅波动，用于避免图表看起来过于理想化。",
    "长期背景维度仍保留 1 到 2 个高关注点，方便说明基因与近期行为的关系。"
  ],
  priorityActions: [
    "分享时强调这里展示的是产品结构和解释逻辑，而不是个人真实结果。",
    "把重点放在“年度体检 + 连续趋势 + 长期背景”三层信息如何合成判断。",
    "如果需要进一步演示行动闭环，可从周报样例切到月报样例讲连续追踪。"
  ],
  continueObserving: [
    "持续保留 8 到 12 周复查窗口，展示短期改善与长期稳定之间的差异。",
    "保留 1 个仍需关注的风险点，便于解释为什么系统不会给出过度乐观结论。",
    "后续如要对外分享，可进一步删减基因卡片和具体数值。"
  ]
});

const latestReports: HealthReportSnapshotRecord[] = [
  createReportRecord({
    id: "share-weekly-2026-03-10",
    reportType: "weekly",
    start: "2026-03-04",
    end: "2026-03-10",
    title: "内部分享样例周报 A",
    headline: "周内执行保持稳定，适合展示系统如何把趋势改善和长期风险放在同一张卡片里。",
    mostImportantChanges: [
      "运动分钟数连续两周保持在较高区间。",
      "睡眠与静息心率的短周期波动明显收敛。"
    ],
    possibleReasons: [
      "训练和作息安排更规律。",
      "示例数据保留了轻微起伏，方便解释噪声与趋势。"
    ],
    priorityActions: [
      "在分享里先讲一周，再过渡到月度。",
      "强调行动建议与指标变化之间的对应关系。"
    ],
    continueObserving: ["继续保留脂代谢与恢复的双轴观察。"]
  }),
  createReportRecord({
    id: "share-weekly-2026-03-03",
    reportType: "weekly",
    start: "2026-02-26",
    end: "2026-03-03",
    title: "内部分享样例周报 B",
    headline: "短期复查样例开始体现出改善，但系统仍保留保守判断，避免把一次回落当成结论。",
    mostImportantChanges: [
      "LDL-C 和 ApoB 延续回落。",
      "体重与体脂率保持同步下降。"
    ],
    possibleReasons: [
      "行为执行的示例稳定性较高。",
      "长期背景提醒仍然存在。"
    ],
    priorityActions: [
      "解释为什么系统会把“改善中”与“仍需观察”同时保留。",
      "展示多维度拆分后的分析结构。"
    ],
    continueObserving: ["继续保留长期背景和年度体检对近期变化的校准作用。"]
  }),
  createReportRecord({
    id: "share-monthly-2026-02-28",
    reportType: "monthly",
    start: "2026-02-01",
    end: "2026-02-28",
    title: "内部分享样例月报",
    headline: "月度视角下，行为执行、连续趋势与年度基线能够形成一致叙事，适合用于产品方案讲解。",
    mostImportantChanges: [
      "脂代谢样例在月度窗口内维持改善。",
      "行为与恢复面板不再彼此冲突。"
    ],
    possibleReasons: [
      "样例数据刻意设计为“可解释但不过分完美”。",
      "基因背景保留少量高关注项，用于展示长期风险。"
    ],
    priorityActions: [
      "分享时先从总览进入，再展开到分维度。",
      "把月报作为“长期追踪能力”的落点。"
    ],
    continueObserving: ["后续如需更强脱敏，可把绝对值进一步离散化。"]
  })
];

export const shareHealthHomePageData: HealthHomePageData = {
  generatedAt,
  disclaimer: shareDisclaimer,
  overviewHeadline: "这是一个适合内部分享的脱敏样例首页，保留了结构、节奏和产品判断方式，但不暴露任何个人真实健康记录。",
  overviewNarrative:
    "页面故意保留了“年度基线、连续指标、行为恢复、长期背景”四层视角，便于讲清系统如何从分维度判断回到综合建议。",
  overviewDigest: {
    headline: "结构化趋势向好，但仍保留长期背景提醒，适合演示“谨慎乐观”的判断风格。",
    summary:
      "示例数据展示的是一条典型的代谢改善路径：近期复查和行为数据出现协同变化，但系统不会只看一次回落，而是继续用年度体检和长期背景做校准。",
    goodSignals: [
      "脂代谢趋势呈缓慢改善，便于演示连续复查的价值。",
      "体重、体脂和运动分钟数在图表上形成一致方向。",
      "睡眠时长与静息心率的波动收敛，恢复维度更稳定。"
    ],
    needsAttention: [
      "仍保留一个高关注长期背景，用于说明系统不会把短期改善误判成问题已结束。",
      "年度体检样例里有接近上边界的指标，适合解释基线与短期数据的关系。",
      "图表中仍保留轻微噪声，提醒用户不要只看单日点位。"
    ],
    longTermRisks: [
      "长期脂代谢背景仍需持续观察。",
      "恢复和训练负荷的平衡仍需要在更长时间窗口验证。",
      "基因面板只作为长期背景，不单独下结论。"
    ],
    actionPlan: [
      "分享时先展示总览，再按体检、复查、行为、背景四层展开。",
      "强调数据已脱敏，重点在于产品如何组织信息和生成建议。",
      "如果需要讲闭环能力，可顺势切到周报和月报样例。"
    ]
  },
  overviewFocusAreas: ["年度基线", "脂代谢趋势", "行为与恢复", "长期背景", "脱敏分享"],
  overviewSpotlights: [
    {
      label: "年度基线",
      value: "2 年样例",
      tone: "neutral",
      detail: "保留同比结构，日期与标题已重写"
    },
    {
      label: "代谢改善",
      value: "LDL-C -0.9",
      tone: "positive",
      detail: "展示“连续复查后缓慢回落”的表达方式"
    },
    {
      label: "行为执行",
      value: "7 / 10 天达标",
      tone: "positive",
      detail: "运动与睡眠样例可支撑行动建议"
    },
    {
      label: "长期背景",
      value: "2 项保留",
      tone: "attention",
      detail: "用于解释为什么系统仍建议继续观察"
    }
  ],
  sourceDimensions: [
    {
      key: "annual_exam",
      label: "年度体检",
      latestAt: "2025-11-16T09:00:00+08:00",
      status: "ready",
      summary: "年度基线样例",
      highlight: "2 年年度样例"
    },
    {
      key: "clinical_labs",
      label: "专项复查",
      latestAt: "2026-03-01T08:30:00+08:00",
      status: "ready",
      summary: "血脂与代谢复查样例",
      highlight: "近 6 个月连续点"
    },
    {
      key: "body_scale",
      label: "体脂秤",
      latestAt: "2026-03-09T07:40:00+08:00",
      status: "ready",
      summary: "体组成趋势样例",
      highlight: "体重与体脂同步"
    },
    {
      key: "activity",
      label: "运动 / 睡眠",
      latestAt: "2026-03-10T06:50:00+08:00",
      status: "ready",
      summary: "活动与恢复样例",
      highlight: "10 天节律数据"
    },
    {
      key: "genetics",
      label: "长期背景",
      latestAt: "2026-01-15T10:20:00+08:00",
      status: "background",
      summary: "长期背景样例",
      highlight: "3 条背景卡片"
    }
  ],
  dimensionAnalyses: [
    {
      key: "integrated",
      kicker: "Integrated View",
      title: "综合判断适合用于内部演示“谨慎乐观”的产品风格",
      summary:
        "示例里最重要的不是某个具体数值，而是系统如何把年度基线、连续复查、行为数据和长期背景组合成一个可解释的综合判断。",
      goodSignals: [
        "近期复查和行为变化方向一致，便于演示行动建议的来源。",
        "多张图表之间的叙事能够互相印证，不会各说各话。",
        "摘要、维度卡片和报告快照之间保持同一套语言。"
      ],
      needsAttention: [
        "保留 1 到 2 个未完全解除的关注点，避免页面显得过度理想化。",
        "分享时仍需明确告知：这是脱敏样例，不代表真实个人状态。",
        "基因与长期背景只做解释层，不应被当成决定性结论。"
      ],
      longTermRisks: [
        "长期脂代谢背景仍需在季度尺度复看。",
        "恢复和训练负荷的平衡需要更长周期验证。",
        "年度体检与近期复查之间可能存在结构性差异。"
      ],
      actionPlan: [
        "先讲综合判断，再依次下钻到四个维度。",
        "把“为什么不是只看一次化验”作为主要产品观点。",
        "最后用周报 / 月报样例收束到持续追踪能力。"
      ],
      metrics: [
        {
          label: "综合状态",
          value: "稳中向好",
          detail: "展示改善趋势，但保留观察语气",
          tone: "positive"
        },
        {
          label: "核心主线",
          value: "脂代谢",
          detail: "最适合串起体检、复查和长期背景",
          tone: "attention"
        },
        {
          label: "行为执行",
          value: "7 / 10 天",
          detail: "用于演示生活方式数据如何进入判断",
          tone: "positive"
        },
        {
          label: "长期背景",
          value: "2 项保留",
          detail: "避免把短期改善解释过头",
          tone: "neutral"
        }
      ]
    },
    {
      key: "annual_exam",
      kicker: "Annual Exam",
      title: "年度体检负责提供慢变量基线",
      summary: "分享页中的年度体检模块主要用于说明：为什么系统需要用年度视角校准近期波动。",
      goodSignals: [
        "BMI 和 ApoB 与上一年度样例相比呈下降。",
        "空腹血糖维持在相对平稳区间。",
        "年度摘要能给近期复查提供解释背景。"
      ],
      needsAttention: [
        "LDL-C 仍接近上边界，适合解释“改善中但未结束”。",
        "体脂率仍是需要继续管理的维度。",
        "年度体检更新频率低，不能单独承担短期判断。"
      ],
      longTermRisks: [
        "单次年度体检无法替代连续追踪。",
        "如果只看年度数据，容易忽略行为变化的短期影响。"
      ],
      actionPlan: [
        "把年度数据作为背景层，不把它当作唯一结论来源。",
        "结合近期复查说明哪些改变是真实延续，哪些只是短期噪声。"
      ],
      metrics: [
        {
          label: "年度重点",
          value: "LDL-C 边缘",
          detail: "适合讲基线如何约束短期乐观判断",
          tone: "attention"
        },
        {
          label: "同比变化",
          value: "BMI -0.9",
          detail: "保留同比结构用于演示",
          tone: "positive"
        },
        {
          label: "稳定指标",
          value: "血糖平稳",
          detail: "提供“没有明显恶化”的背景",
          tone: "neutral"
        },
        {
          label: "展示作用",
          value: "慢变量层",
          detail: "与连续复查形成互补",
          tone: "neutral"
        }
      ]
    },
    {
      key: "clinical_labs",
      kicker: "Clinical Labs",
      title: "专项复查负责呈现近期起效",
      summary:
        "这里保留多次血脂与代谢样例点位，用来演示系统如何识别“短期变化已经开始发生，但仍需继续确认”。",
      goodSignals: [
        "LDL-C 与 ApoB 在连续点位上共同回落。",
        "波动幅度控制在合理范围内，图表更接近真实世界。",
        "近期复查能直接支撑行动建议的更新。"
      ],
      needsAttention: [
        "Lp(a) 仍维持高背景，适合解释长期风险。",
        "单次回落不能被当成长期结论。",
        "近期改善仍需与年度基线一起解释。"
      ],
      longTermRisks: [
        "如果停止连续复查，系统会失去对短期变化的分辨力。",
        "长期背景项可能限制某些指标的改善速度。"
      ],
      actionPlan: [
        "用复查曲线说明产品如何把“改善中”而非“已解决”表达出来。",
        "保留 8 到 12 周的复查窗口用于持续验证。"
      ],
      metrics: [
        {
          label: "LDL-C",
          value: "2.8 mmol/L",
          detail: "6 个月趋势缓慢下降",
          tone: "positive"
        },
        {
          label: "ApoB",
          value: "0.88 g/L",
          detail: "与 LDL-C 呈一致方向",
          tone: "positive"
        },
        {
          label: "Lp(a)",
          value: "47 mg/dL",
          detail: "作为长期背景保留",
          tone: "attention"
        },
        {
          label: "展示作用",
          value: "短期起效",
          detail: "支撑行动建议更新",
          tone: "neutral"
        }
      ]
    },
    {
      key: "activity_recovery",
      kicker: "Activity & Recovery",
      title: "行为和恢复维度负责解释“为什么会变”",
      summary:
        "分享时可以用这组面板解释系统不是只给结论，而是会把运动、睡眠和恢复节律一起带回到判断里。",
      goodSignals: [
        "运动分钟数与活跃能量维持在较稳定区间。",
        "睡眠时长略有改善，静息心率轻度回落。",
        "行为数据与复查趋势之间可以建立解释关系。"
      ],
      needsAttention: [
        "周内仍保留个别起伏，方便说明噪声与趋势的区别。",
        "恢复改善通常慢于行为变化，分享时应避免过度归因。"
      ],
      longTermRisks: [
        "如果行为执行中断，短期改善可能难以延续。",
        "恢复维度的稳定性仍需要更长时间窗口。"
      ],
      actionPlan: [
        "用 10 天或 30 天视图展示节律变化。",
        "把行为数据作为解释层，而不是单独评价优劣。"
      ],
      metrics: [
        {
          label: "运动分钟",
          value: "46 min",
          detail: "近 10 天多数样例达标",
          tone: "positive"
        },
        {
          label: "睡眠时长",
          value: "7.0 h",
          detail: "展示恢复维度的平稳改善",
          tone: "positive"
        },
        {
          label: "静息心率",
          value: "62 bpm",
          detail: "恢复压力略有缓和",
          tone: "neutral"
        },
        {
          label: "展示作用",
          value: "解释原因",
          detail: "说明为什么近期复查在变",
          tone: "neutral"
        }
      ]
    },
    {
      key: "genetics",
      kicker: "Long-term Context",
      title: "长期背景维度只负责拉长时间尺度",
      summary:
        "这里不展示真实基因信息，而是用通用编码卡片说明系统如何把长期背景纳入解释，但不把它当作结论本身。",
      goodSignals: [
        "长期背景卡片能够帮助解释为什么不同人的改善速度会不同。",
        "界面上把背景层与近期行为层做了明确分离。"
      ],
      needsAttention: [
        "高关注背景仍然存在，系统不会给出过度乐观表述。",
        "分享时需要明确：背景信息只能辅助解释，不代表诊断。"
      ],
      longTermRisks: [
        "长期背景会影响对脂代谢和恢复的预期管理。",
        "如果用户只看背景结论，容易忽略生活方式干预价值。"
      ],
      actionPlan: [
        "用背景卡片说明“为什么要持续跟踪”。",
        "强调近期行为与长期背景需要一起看。"
      ],
      metrics: [
        {
          label: "背景卡片",
          value: "3 条",
          detail: "全部为通用编码示例",
          tone: "neutral"
        },
        {
          label: "高关注项",
          value: "1 条",
          detail: "保留长期观察语境",
          tone: "attention"
        },
        {
          label: "关联指标",
          value: "2 条",
          detail: "和脂代谢、恢复维度互相呼应",
          tone: "neutral"
        },
        {
          label: "展示作用",
          value: "长期背景",
          detail: "避免单看短期结果",
          tone: "positive"
        }
      ]
    }
  ],
  importOptions: [],
  overviewCards: [
    {
      metric_code: "share.ldl",
      label: "LDL-C",
      value: "2.8 mmol/L",
      trend: "近 6 个月缓慢下降，适合演示连续复查价值",
      status: "improving",
      abnormal_flag: "normal",
      meaning: "这里是演示用示例值，用于说明多次复查比单点结果更有解释力。"
    },
    {
      metric_code: "share.apob",
      label: "ApoB",
      value: "0.88 g/L",
      trend: "与 LDL-C 方向一致，强化综合判断",
      status: "improving",
      abnormal_flag: "normal",
      meaning: "适合在分享中说明系统会优先抓取共同变化的指标。"
    },
    {
      metric_code: "share.bodyfat",
      label: "体脂率",
      value: "22.9 %",
      trend: "与体重同步下降，便于解释行为影响",
      status: "stable",
      abnormal_flag: "borderline",
      meaning: "保留轻度边缘状态，更贴近真实趋势展示。"
    },
    {
      metric_code: "share.sleep",
      label: "睡眠时长",
      value: "7.0 h",
      trend: "近 10 天波动收敛，用于展示恢复维度",
      status: "stable",
      abnormal_flag: "normal",
      meaning: "行为和恢复数据主要用来解释“为什么会变”。"
    }
  ],
  annualExam: {
    latestTitle: "年度体检样例 2025",
    latestRecordedAt: "2025-11-16T09:00:00+08:00",
    previousTitle: "年度体检样例 2024",
    metrics: [
      {
        metricCode: "lipid.ldl_c",
        label: "低密度脂蛋白胆固醇",
        shortLabel: "LDL-C",
        unit: "mmol/L",
        latestValue: 3.18,
        previousValue: 3.44,
        delta: -0.26,
        abnormalFlag: "borderline",
        referenceRange: "<3.40 mmol/L",
        meaning: "用于展示年度基线如何校准近期复查的改善判断。",
        practicalAdvice: "分享时可以把它作为“仍需观察但方向变好”的示例。"
      },
      {
        metricCode: "lipid.apob",
        label: "载脂蛋白 B",
        shortLabel: "ApoB",
        unit: "g/L",
        latestValue: 0.93,
        previousValue: 1.02,
        delta: -0.09,
        abnormalFlag: "normal",
        referenceRange: "0.80-1.10 g/L",
        meaning: "适合说明系统会优先识别与核心风险同向变化的指标。",
        practicalAdvice: "与 LDL-C 放在一起讲，更容易解释综合判断。"
      },
      {
        metricCode: "body.body_fat_pct",
        label: "体脂率",
        shortLabel: "体脂率",
        unit: "%",
        latestValue: 23.6,
        previousValue: 24.8,
        delta: -1.2,
        abnormalFlag: "borderline",
        referenceRange: "10-20 %",
        meaning: "帮助说明体重下降是否伴随体组成改善。",
        practicalAdvice: "可以作为行为数据和体检数据之间的桥梁指标。"
      },
      {
        metricCode: "glycemic.glucose",
        label: "空腹血糖",
        shortLabel: "血糖",
        unit: "mmol/L",
        latestValue: 5.4,
        previousValue: 5.52,
        delta: -0.12,
        abnormalFlag: "normal",
        referenceRange: "3.90-6.10 mmol/L",
        meaning: "提供“无明显恶化”的稳定背景，避免页面只强调风险。",
        practicalAdvice: "分享时用来体现系统也会识别稳定信号。"
      }
    ],
    abnormalMetricLabels: ["LDL-C 接近上边界", "体脂率仍偏高"],
    improvedMetricLabels: ["BMI", "ApoB", "空腹血糖"],
    highlightSummary: "年度样例保留了“有改善但仍需观察”的典型结构，适合解释系统的保守表达风格。",
    actionSummary: "把年度体检放在背景层，和近期复查及行为数据一起理解。"
  },
  geneticFindings: [
    {
      id: "share-gene-1",
      geneSymbol: "LIP-01",
      traitLabel: "脂代谢慢响应型",
      dimension: "脂代谢背景",
      riskLevel: "high",
      evidenceLevel: "A",
      summary: "用于演示长期背景如何限制短期改善的解读，不代表任何真实基因结论。",
      suggestion: "在分享中说明：即使趋势改善，系统仍会保留长期观察建议。",
      recordedAt: "2026-01-15T10:20:00+08:00",
      linkedMetricLabel: "LDL-C",
      linkedMetricValue: "2.8 mmol/L（示例）",
      linkedMetricFlag: "长期观察",
      plainMeaning: "这类背景通常意味着需要更长时间窗口评估改善是否稳定。",
      practicalAdvice: "在产品表达上，将其放在“长期背景”而不是“当前异常”区域。"
    },
    {
      id: "share-gene-2",
      geneSymbol: "RCV-07",
      traitLabel: "恢复敏感型",
      dimension: "恢复与睡眠",
      riskLevel: "medium",
      evidenceLevel: "B",
      summary: "用于展示恢复维度为什么需要和运动负荷一起解释。",
      suggestion: "把行为改善与恢复波动同时展示，避免只看训练完成度。",
      recordedAt: "2026-01-15T10:20:00+08:00",
      linkedMetricLabel: "睡眠时长",
      linkedMetricValue: "7.0 h（示例）",
      linkedMetricFlag: "节律改善",
      plainMeaning: "这类背景更适合放在长期节律管理语境里看。",
      practicalAdvice: "投屏分享时可用它说明系统为什么会推荐更稳的节奏，而不是更激进的训练。"
    },
    {
      id: "share-gene-3",
      geneSymbol: "WGT-12",
      traitLabel: "体重管理阻力型",
      dimension: "体重管理",
      riskLevel: "low",
      evidenceLevel: "B",
      summary: "用于演示长期背景卡片的层次关系，让页面不只围绕血脂展开。",
      suggestion: "保持长期趋势视角，不把短期平台期直接解释为失败。",
      recordedAt: "2026-01-15T10:20:00+08:00",
      plainMeaning: "这类背景更多影响预期管理，而不是改变当下行动方向。",
      practicalAdvice: "可以作为体脂率与体重趋势图的补充解释。"
    }
  ],
  keyReminders: [],
  watchItems: [],
  latestNarrative,
  charts: {
    lipid: {
      title: "脂代谢趋势样例",
      description: "保留复查节奏与多指标联动，但具体数值已重写，用于演示系统如何识别一致方向的改善。",
      defaultRange: "all",
      data: [
        createTrendPoint("2025-10-01", { ldl: 3.7, apob: 1.06, lpa: 52 }),
        createTrendPoint("2025-11-01", { ldl: 3.5, apob: 1.01, lpa: 51 }),
        createTrendPoint("2025-12-01", { ldl: 3.3, apob: 0.97, lpa: 50 }),
        createTrendPoint("2026-01-01", { ldl: 3.1, apob: 0.93, lpa: 48 }),
        createTrendPoint("2026-02-01", { ldl: 2.9, apob: 0.9, lpa: 48 }),
        createTrendPoint("2026-03-01", { ldl: 2.8, apob: 0.88, lpa: 47 })
      ],
      lines: [
        { key: "ldl", label: "LDL-C", color: "#0f766e", unit: "mmol/L", yAxisId: "left" },
        { key: "apob", label: "ApoB", color: "#0284c7", unit: "g/L", yAxisId: "left" },
        { key: "lpa", label: "Lp(a)", color: "#ea580c", unit: "mg/dL", yAxisId: "right" }
      ]
    },
    bodyComposition: {
      title: "体组成趋势样例",
      description: "体重、体脂和骨骼肌率被设计成可互相解释的趋势，用于演示体组成面板的表达方式。",
      defaultRange: "all",
      data: [
        createTrendPoint("2025-10-01", { weight: 84.0, bodyFat: 25.8, muscle: 38.5 }),
        createTrendPoint("2025-11-01", { weight: 83.2, bodyFat: 25.3, muscle: 38.7 }),
        createTrendPoint("2025-12-01", { weight: 82.5, bodyFat: 24.7, muscle: 39.0 }),
        createTrendPoint("2026-01-01", { weight: 81.6, bodyFat: 24.1, muscle: 39.2 }),
        createTrendPoint("2026-02-01", { weight: 80.8, bodyFat: 23.4, muscle: 39.4 }),
        createTrendPoint("2026-03-01", { weight: 80.3, bodyFat: 22.9, muscle: 39.6 })
      ],
      lines: [
        { key: "weight", label: "体重", color: "#0f766e", unit: "kg", yAxisId: "left" },
        { key: "bodyFat", label: "体脂率", color: "#ea580c", unit: "%", yAxisId: "right" },
        { key: "muscle", label: "骨骼肌率", color: "#2563eb", unit: "%", yAxisId: "right" }
      ]
    },
    activity: {
      title: "运动执行样例",
      description: "近 10 天活动样例用于说明行动数据如何进入首页判断，而不是只做记录展示。",
      defaultRange: "30d",
      data: [
        createTrendPoint("2026-03-01", { exerciseMinutes: 28, activeKcal: 320 }),
        createTrendPoint("2026-03-02", { exerciseMinutes: 32, activeKcal: 360 }),
        createTrendPoint("2026-03-03", { exerciseMinutes: 35, activeKcal: 380 }),
        createTrendPoint("2026-03-04", { exerciseMinutes: 40, activeKcal: 410 }),
        createTrendPoint("2026-03-05", { exerciseMinutes: 38, activeKcal: 390 }),
        createTrendPoint("2026-03-06", { exerciseMinutes: 45, activeKcal: 440 }),
        createTrendPoint("2026-03-07", { exerciseMinutes: 48, activeKcal: 470 }),
        createTrendPoint("2026-03-08", { exerciseMinutes: 42, activeKcal: 430 }),
        createTrendPoint("2026-03-09", { exerciseMinutes: 50, activeKcal: 490 }),
        createTrendPoint("2026-03-10", { exerciseMinutes: 46, activeKcal: 460 })
      ],
      lines: [
        {
          key: "exerciseMinutes",
          label: "运动分钟",
          color: "#0f766e",
          unit: "min",
          yAxisId: "left"
        },
        {
          key: "activeKcal",
          label: "活跃能量",
          color: "#ea580c",
          unit: "kcal",
          yAxisId: "right"
        }
      ]
    },
    recovery: {
      title: "恢复节律样例",
      description: "睡眠时长和静息心率用于演示恢复维度如何补充解释近期表现。",
      defaultRange: "30d",
      data: [
        createTrendPoint("2026-03-01", { sleepHours: 6.2, restingHr: 66 }),
        createTrendPoint("2026-03-02", { sleepHours: 6.6, restingHr: 65 }),
        createTrendPoint("2026-03-03", { sleepHours: 6.9, restingHr: 65 }),
        createTrendPoint("2026-03-04", { sleepHours: 7.1, restingHr: 64 }),
        createTrendPoint("2026-03-05", { sleepHours: 6.7, restingHr: 64 }),
        createTrendPoint("2026-03-06", { sleepHours: 7.0, restingHr: 63 }),
        createTrendPoint("2026-03-07", { sleepHours: 7.2, restingHr: 63 }),
        createTrendPoint("2026-03-08", { sleepHours: 6.8, restingHr: 64 }),
        createTrendPoint("2026-03-09", { sleepHours: 7.1, restingHr: 63 }),
        createTrendPoint("2026-03-10", { sleepHours: 7.0, restingHr: 62 })
      ],
      lines: [
        { key: "sleepHours", label: "睡眠时长", color: "#0f766e", unit: "h", yAxisId: "left" },
        { key: "restingHr", label: "静息心率", color: "#2563eb", unit: "bpm", yAxisId: "right" }
      ]
    }
  },
  latestReports
};
