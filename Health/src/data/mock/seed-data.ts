import type {
  DataSourceSeed,
  GeneticFindingSeed,
  MeasurementSeed,
  MeasurementSetKind,
  MeasurementSetSeed,
  MetricCatalogItem,
  UserSeed
} from "../../server/domain/types";

export const NON_DIAGNOSTIC_DISCLAIMER =
  "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。";

export const seedVersion = "stage-1-2026-03-08";

export const users: UserSeed[] = [
  {
    id: "user-self",
    displayName: "马尧",
    sex: "male",
    birthYear: 1988,
    heightCm: 180,
    note: "单用户 local-first 首版默认账号"
  }
];

export const dataSources: DataSourceSeed[] = [
  {
    id: "source-annual-exam",
    sourceType: "annual_exam_pdf",
    name: "年度体检报告",
    vendor: "综合体检中心",
    ingestChannel: "file",
    note: "用于承载历年体检 PDF 导入结果"
  },
  {
    id: "source-lipid-panel",
    sourceType: "special_lab_pdf",
    name: "血脂专项复查",
    vendor: "上海市第六人民医院徐汇院区",
    ingestChannel: "file",
    note: "来自近期专项生化与脂蛋白检测样本"
  },
  {
    id: "source-body-scale",
    sourceType: "body_scale_app",
    name: "Fitdays 体脂秤",
    vendor: "Fitdays",
    ingestChannel: "manual",
    note: "当前以手工录入或 mock 方式接入"
  },
  {
    id: "source-apple-health",
    sourceType: "wearable_export",
    name: "Apple Health",
    vendor: "Apple",
    ingestChannel: "manual",
    note: "后续优先支持 Health 导出文件导入"
  },
  {
    id: "source-gene-report",
    sourceType: "gene_pdf",
    name: "基因检测报告",
    vendor: "Gene 微基因",
    ingestChannel: "mock",
    note: "当前为 schema 与演示 mock，后续再接真实报告"
  }
];

export const metricCatalog: MetricCatalogItem[] = [
  {
    code: "body.weight",
    label: "体重",
    shortLabel: "体重",
    category: "body",
    defaultUnit: "kg",
    betterDirection: "down",
    normalLow: 60.6,
    normalHigh: 82,
    referenceText: "样例体脂秤推荐范围 60.6-82.0 kg",
    description: "用于观察总体体重趋势，并与体脂和运动负荷联动分析。"
  },
  {
    code: "body.bmi",
    label: "BMI",
    shortLabel: "BMI",
    category: "body",
    defaultUnit: "kg/m2",
    betterDirection: "down",
    normalLow: 18.5,
    normalHigh: 24.9,
    referenceText: "18.5-24.9",
    description: "结合身高与体重得到的总体体型指标。"
  },
  {
    code: "body.body_fat_pct",
    label: "体脂率",
    shortLabel: "体脂率",
    category: "body",
    defaultUnit: "%",
    betterDirection: "down",
    normalLow: 10,
    normalHigh: 20,
    referenceText: "样例体脂秤展示区间 10-20% 为标准附近",
    description: "首版重点跟踪脂肪变化，不单看体重。"
  },
  {
    code: "body.water_pct",
    label: "体水分",
    shortLabel: "体水分",
    category: "body",
    defaultUnit: "%",
    betterDirection: "up",
    description: "用于辅助解释体重波动和体脂秤短期变化。"
  },
  {
    code: "body.skeletal_muscle_pct",
    label: "骨骼肌率",
    shortLabel: "骨骼肌率",
    category: "body",
    defaultUnit: "%",
    betterDirection: "up",
    description: "配合体脂率一起看，避免减重时肌肉流失。"
  },
  {
    code: "body.visceral_fat_level",
    label: "内脏脂肪等级",
    shortLabel: "内脏脂肪",
    category: "body",
    defaultUnit: "level",
    betterDirection: "down",
    description: "用于评估腹部脂肪相关风险趋势。"
  },
  {
    code: "body.basal_metabolism",
    label: "基础代谢率",
    shortLabel: "基础代谢",
    category: "body",
    defaultUnit: "kcal",
    betterDirection: "neutral",
    description: "首版作为参考展示，不作强规则判断。"
  },
  {
    code: "body.lean_mass",
    label: "去脂体重",
    shortLabel: "去脂体重",
    category: "body",
    defaultUnit: "kg",
    betterDirection: "up",
    description: "辅助判断减重过程中的瘦体重变化。"
  },
  {
    code: "lipid.total_cholesterol",
    label: "总胆固醇",
    shortLabel: "TC",
    category: "lipid",
    defaultUnit: "mmol/L",
    betterDirection: "down",
    normalHigh: 5.2,
    referenceText: "<5.20 mmol/L",
    description: "血脂总览指标，需结合 LDL-C、TG、HDL-C 一起看。"
  },
  {
    code: "lipid.triglycerides",
    label: "甘油三酯",
    shortLabel: "TG",
    category: "lipid",
    defaultUnit: "mmol/L",
    betterDirection: "down",
    normalHigh: 1.7,
    referenceText: "<1.70 mmol/L",
    description: "与体重、饮食和运动相关性较强。"
  },
  {
    code: "lipid.hdl_c",
    label: "高密度脂蛋白胆固醇",
    shortLabel: "HDL-C",
    category: "lipid",
    defaultUnit: "mmol/L",
    betterDirection: "up",
    normalLow: 1.04,
    referenceText: ">1.04 mmol/L",
    description: "血脂结构中的保护性指标之一。"
  },
  {
    code: "lipid.ldl_c",
    label: "低密度脂蛋白胆固醇",
    shortLabel: "LDL-C",
    category: "lipid",
    defaultUnit: "mmol/L",
    betterDirection: "down",
    normalHigh: 3.4,
    referenceText: "<3.40 mmol/L",
    description: "首版风险提示的核心规则指标之一。"
  },
  {
    code: "lipid.apoa1",
    label: "载脂蛋白 A1",
    shortLabel: "ApoA1",
    category: "lipid",
    defaultUnit: "g/L",
    betterDirection: "up",
    normalLow: 1.2,
    normalHigh: 1.6,
    description: "用于补充脂蛋白结构信息。"
  },
  {
    code: "lipid.apob",
    label: "载脂蛋白 B",
    shortLabel: "ApoB",
    category: "lipid",
    defaultUnit: "g/L",
    betterDirection: "down",
    normalLow: 0.8,
    normalHigh: 1.1,
    description: "可用于配合 LDL-C 和 Lp(a) 看脂蛋白颗粒负荷。"
  },
  {
    code: "lipid.lpa",
    label: "脂蛋白(a)",
    shortLabel: "Lp(a)",
    category: "lipid",
    defaultUnit: "mg/dL",
    betterDirection: "down",
    normalHigh: 30,
    referenceText: "<30.0 mg/dL",
    description: "首版长期关注指标，倾向看慢变量而非短期噪声。"
  },
  {
    code: "renal.creatinine",
    label: "肌酐",
    shortLabel: "肌酐",
    category: "renal",
    defaultUnit: "umol/L",
    betterDirection: "down",
    normalLow: 57,
    normalHigh: 97,
    description: "肾功能基础指标，配合 eGFR 解释。"
  },
  {
    code: "renal.egfr",
    label: "估算肾小球滤过率",
    shortLabel: "eGFR",
    category: "renal",
    defaultUnit: "mL/min/1.73m2",
    betterDirection: "up",
    normalLow: 90,
    description: "用于长期观察肾功能估算值。"
  },
  {
    code: "renal.uric_acid",
    label: "尿酸",
    shortLabel: "尿酸",
    category: "renal",
    defaultUnit: "umol/L",
    betterDirection: "down",
    normalLow: 240,
    normalHigh: 420,
    description: "与饮食、体重变化和代谢状态联动观察。"
  },
  {
    code: "glycemic.glucose",
    label: "血糖",
    shortLabel: "血糖",
    category: "glycemic",
    defaultUnit: "mmol/L",
    betterDirection: "down",
    normalLow: 3.9,
    normalHigh: 6.09,
    description: "首版保留为基础代谢指标，不做诊断解读。"
  },
  {
    code: "activity.active_kcal",
    label: "活动能量",
    shortLabel: "活动能量",
    category: "activity",
    defaultUnit: "kcal",
    betterDirection: "up",
    description: "由 Apple Health 提供的日活动能量估计。"
  },
  {
    code: "activity.exercise_minutes",
    label: "训练分钟",
    shortLabel: "训练",
    category: "activity",
    defaultUnit: "min",
    betterDirection: "up",
    description: "用于评估运动执行度。"
  },
  {
    code: "activity.stand_hours",
    label: "站立小时",
    shortLabel: "站立",
    category: "activity",
    defaultUnit: "h",
    betterDirection: "up",
    description: "用于观察久坐改善。"
  },
  {
    code: "activity.resting_kcal",
    label: "静息能量",
    shortLabel: "静息能量",
    category: "activity",
    defaultUnit: "kcal",
    betterDirection: "neutral",
    description: "展示代谢基础负荷，不用于风险结论。"
  },
  {
    code: "sleep.in_bed_minutes",
    label: "卧床时间",
    shortLabel: "卧床",
    category: "sleep",
    defaultUnit: "min",
    betterDirection: "up",
    description: "反映睡眠机会窗口。"
  },
  {
    code: "sleep.asleep_minutes",
    label: "睡眠时间",
    shortLabel: "睡眠",
    category: "sleep",
    defaultUnit: "min",
    betterDirection: "up",
    description: "用于观察日常恢复质量。"
  }
];

function measurement(
  metricCode: string,
  value: number,
  unit: string,
  options: Omit<MeasurementSeed, "metricCode" | "value" | "unit"> = {}
): MeasurementSeed {
  return {
    metricCode,
    value,
    unit,
    normalizedValue: options.normalizedValue ?? value,
    normalizedUnit: options.normalizedUnit ?? unit,
    referenceLow: options.referenceLow,
    referenceHigh: options.referenceHigh,
    abnormalFlag: options.abnormalFlag ?? "normal",
    note: options.note,
    rawValue: options.rawValue
  };
}

function measurementSet(
  id: string,
  sourceId: string,
  kind: MeasurementSetKind,
  title: string,
  recordedAt: string,
  measurements: MeasurementSeed[],
  note?: string,
  rawPayload?: Record<string, unknown>
): MeasurementSetSeed {
  return {
    id,
    sourceId,
    kind,
    title,
    recordedAt,
    reportDate: recordedAt.slice(0, 10),
    note,
    rawPayload,
    measurements
  };
}

const annualExamSets: MeasurementSetSeed[] = [
  measurementSet(
    "annual-exam-2024",
    "source-annual-exam",
    "annual_exam",
    "2024 年度体检",
    "2024-08-18T08:20:00+08:00",
    [
      measurement("body.weight", 85.1, "kg"),
      measurement("body.bmi", 26.3, "kg/m2", {
        referenceLow: 18.5,
        referenceHigh: 24.9,
        abnormalFlag: "high"
      }),
      measurement("glycemic.glucose", 5.66, "mmol/L", {
        referenceLow: 3.9,
        referenceHigh: 6.09
      }),
      measurement("renal.creatinine", 99.4, "umol/L", {
        referenceLow: 57,
        referenceHigh: 97,
        abnormalFlag: "high"
      }),
      measurement("renal.uric_acid", 420, "umol/L", {
        referenceLow: 240,
        referenceHigh: 420
      }),
      measurement("lipid.total_cholesterol", 5.62, "mmol/L", {
        referenceHigh: 5.2,
        abnormalFlag: "high"
      }),
      measurement("lipid.triglycerides", 1.43, "mmol/L", {
        referenceHigh: 1.7
      }),
      measurement("lipid.hdl_c", 1.07, "mmol/L", {
        referenceLow: 1.04
      }),
      measurement("lipid.ldl_c", 3.71, "mmol/L", {
        referenceHigh: 3.4,
        abnormalFlag: "high"
      })
    ],
    "样例体检数据，用于演示历年趋势接入。"
  ),
  measurementSet(
    "annual-exam-2025",
    "source-annual-exam",
    "annual_exam",
    "2025 年度体检",
    "2025-09-21T08:40:00+08:00",
    [
      measurement("body.weight", 83.4, "kg"),
      measurement("body.bmi", 25.7, "kg/m2", {
        referenceLow: 18.5,
        referenceHigh: 24.9,
        abnormalFlag: "high"
      }),
      measurement("glycemic.glucose", 5.51, "mmol/L", {
        referenceLow: 3.9,
        referenceHigh: 6.09
      }),
      measurement("renal.creatinine", 96.5, "umol/L", {
        referenceLow: 57,
        referenceHigh: 97
      }),
      measurement("renal.uric_acid", 399, "umol/L", {
        referenceLow: 240,
        referenceHigh: 420
      }),
      measurement("lipid.total_cholesterol", 5.43, "mmol/L", {
        referenceHigh: 5.2,
        abnormalFlag: "high"
      }),
      measurement("lipid.triglycerides", 1.28, "mmol/L", {
        referenceHigh: 1.7
      }),
      measurement("lipid.hdl_c", 1.14, "mmol/L", {
        referenceLow: 1.04
      }),
      measurement("lipid.ldl_c", 3.48, "mmol/L", {
        referenceHigh: 3.4,
        abnormalFlag: "high"
      })
    ],
    "首版作为历年体检趋势样本。"
  )
];

const lipidPanelSets: MeasurementSetSeed[] = [
  measurementSet(
    "lipid-panel-2026-01-04",
    "source-lipid-panel",
    "lipid_panel",
    "血脂专项复查 2026-01-04",
    "2026-01-04T10:16:49+08:00",
    [
      measurement("renal.creatinine", 103.8, "umol/L", {
        referenceLow: 57,
        referenceHigh: 97,
        abnormalFlag: "high"
      }),
      measurement("renal.egfr", 78.19, "mL/min/1.73m2", {
        referenceLow: 90,
        abnormalFlag: "low"
      }),
      measurement("renal.uric_acid", 404, "umol/L", {
        referenceLow: 240,
        referenceHigh: 420
      }),
      measurement("glycemic.glucose", 5.78, "mmol/L", {
        referenceLow: 3.9,
        referenceHigh: 6.09
      }),
      measurement("lipid.total_cholesterol", 5.81, "mmol/L", {
        referenceHigh: 5.2,
        abnormalFlag: "high"
      }),
      measurement("lipid.triglycerides", 1.11, "mmol/L", {
        referenceHigh: 1.7
      }),
      measurement("lipid.hdl_c", 1.18, "mmol/L", {
        referenceLow: 1.04
      }),
      measurement("lipid.ldl_c", 3.62, "mmol/L", {
        referenceHigh: 3.4,
        abnormalFlag: "high"
      }),
      measurement("lipid.apoa1", 1.46, "g/L", {
        referenceLow: 1.2,
        referenceHigh: 1.6
      }),
      measurement("lipid.apob", 1.05, "g/L", {
        referenceLow: 0.8,
        referenceHigh: 1.1
      }),
      measurement("lipid.lpa", 66.3, "mg/dL", {
        referenceHigh: 30,
        abnormalFlag: "high"
      })
    ],
    "直接来源于用户提供截图中的近期专项生化结果。"
  ),
  measurementSet(
    "lipid-panel-2026-01-19",
    "source-lipid-panel",
    "lipid_panel",
    "血脂专项复查 2026-01-19",
    "2026-01-19T11:00:41+08:00",
    [
      measurement("renal.creatinine", 93.7, "umol/L", {
        referenceLow: 57,
        referenceHigh: 97
      }),
      measurement("renal.egfr", 88.47, "mL/min/1.73m2", {
        referenceLow: 90,
        abnormalFlag: "low"
      }),
      measurement("renal.uric_acid", 378, "umol/L", {
        referenceLow: 240,
        referenceHigh: 420
      }),
      measurement("lipid.total_cholesterol", 2.56, "mmol/L"),
      measurement("lipid.triglycerides", 0.63, "mmol/L"),
      measurement("lipid.hdl_c", 1.32, "mmol/L"),
      measurement("lipid.ldl_c", 0.92, "mmol/L"),
      measurement("lipid.apoa1", 1.56, "g/L"),
      measurement("lipid.apob", 0.37, "g/L", {
        referenceLow: 0.8,
        abnormalFlag: "low"
      }),
      measurement("lipid.lpa", 56.8, "mg/dL", {
        referenceHigh: 30,
        abnormalFlag: "high"
      })
    ],
    "显示出短期干预后 LDL-C 与 TC 的明显下降。"
  ),
  measurementSet(
    "lipid-panel-2026-02-11",
    "source-lipid-panel",
    "lipid_panel",
    "血脂专项复查 2026-02-11",
    "2026-02-11T09:32:17+08:00",
    [
      measurement("lipid.total_cholesterol", 3.45, "mmol/L"),
      measurement("lipid.triglycerides", 1.27, "mmol/L"),
      measurement("lipid.hdl_c", 1.18, "mmol/L"),
      measurement("lipid.ldl_c", 1.64, "mmol/L"),
      measurement("lipid.apoa1", 1.48, "g/L"),
      measurement("lipid.apob", 0.6, "g/L", {
        referenceLow: 0.8,
        abnormalFlag: "low"
      }),
      measurement("lipid.lpa", 61.6, "mg/dL", {
        referenceHigh: 30,
        abnormalFlag: "high"
      })
    ],
    "近期复查显示 LDL-C 仍维持较低，而 Lp(a) 依旧偏高。"
  )
];

const bodyCompositionSets: MeasurementSetSeed[] = [
  measurementSet(
    "body-comp-2025-11-23",
    "source-body-scale",
    "body_composition",
    "体脂秤周统计 2025-11-23",
    "2025-11-23T08:12:00+08:00",
    [
      measurement("body.weight", 82.1, "kg"),
      measurement("body.bmi", 25.3, "kg/m2", {
        referenceLow: 18.5,
        referenceHigh: 24.9,
        abnormalFlag: "high"
      }),
      measurement("body.body_fat_pct", 24.1, "%", {
        abnormalFlag: "high"
      }),
      measurement("body.water_pct", 55.6, "%"),
      measurement("body.skeletal_muscle_pct", 43.2, "%"),
      measurement("body.basal_metabolism", 1715, "kcal"),
      measurement("body.lean_mass", 62.3, "kg"),
      measurement("body.visceral_fat_level", 7, "level")
    ]
  ),
  measurementSet(
    "body-comp-2025-12-13",
    "source-body-scale",
    "body_composition",
    "体脂秤周统计 2025-12-13",
    "2025-12-13T08:10:00+08:00",
    [
      measurement("body.weight", 81.7, "kg"),
      measurement("body.bmi", 25.2, "kg/m2", {
        abnormalFlag: "high"
      }),
      measurement("body.body_fat_pct", 23.9, "%", {
        abnormalFlag: "high"
      }),
      measurement("body.water_pct", 55.8, "%"),
      measurement("body.skeletal_muscle_pct", 43.4, "%"),
      measurement("body.basal_metabolism", 1712, "kcal"),
      measurement("body.lean_mass", 62.1, "kg"),
      measurement("body.visceral_fat_level", 7, "level")
    ]
  ),
  measurementSet(
    "body-comp-2026-01-04",
    "source-body-scale",
    "body_composition",
    "体脂秤周统计 2026-01-04",
    "2026-01-04T08:09:00+08:00",
    [
      measurement("body.weight", 81.3, "kg"),
      measurement("body.bmi", 25.1, "kg/m2", {
        abnormalFlag: "high"
      }),
      measurement("body.body_fat_pct", 23.4, "%", {
        abnormalFlag: "high"
      }),
      measurement("body.water_pct", 56.1, "%"),
      measurement("body.skeletal_muscle_pct", 43.7, "%"),
      measurement("body.basal_metabolism", 1705, "kcal"),
      measurement("body.lean_mass", 61.9, "kg"),
      measurement("body.visceral_fat_level", 6, "level")
    ]
  ),
  measurementSet(
    "body-comp-2026-02-15",
    "source-body-scale",
    "body_composition",
    "体脂秤周统计 2026-02-15",
    "2026-02-15T08:16:00+08:00",
    [
      measurement("body.weight", 80.6, "kg"),
      measurement("body.bmi", 24.8, "kg/m2"),
      measurement("body.body_fat_pct", 23.1, "%", {
        abnormalFlag: "high"
      }),
      measurement("body.water_pct", 56.4, "%"),
      measurement("body.skeletal_muscle_pct", 43.9, "%"),
      measurement("body.basal_metabolism", 1698, "kcal"),
      measurement("body.lean_mass", 61.5, "kg"),
      measurement("body.visceral_fat_level", 6, "level")
    ]
  ),
  measurementSet(
    "body-comp-2026-03-06",
    "source-body-scale",
    "body_composition",
    "体脂秤周统计 2026-03-06",
    "2026-03-06T08:11:43+08:00",
    [
      measurement("body.weight", 78.9, "kg"),
      measurement("body.bmi", 24.4, "kg/m2"),
      measurement("body.body_fat_pct", 22.5, "%", {
        abnormalFlag: "high"
      }),
      measurement("body.water_pct", 56.9, "%"),
      measurement("body.skeletal_muscle_pct", 44.1, "%"),
      measurement("body.basal_metabolism", 1691, "kcal"),
      measurement("body.lean_mass", 61.1, "kg"),
      measurement("body.visceral_fat_level", 6, "level")
    ],
    "直接参考体脂秤截图样本。"
  )
];

const activityDays = [
  ["2026-02-23", 284, 42, 8, 1768],
  ["2026-02-24", 326, 45, 9, 1771],
  ["2026-02-25", 301, 38, 9, 1776],
  ["2026-02-26", 348, 52, 10, 1770],
  ["2026-02-27", 372, 64, 9, 1764],
  ["2026-02-28", 294, 35, 8, 1758],
  ["2026-03-01", 317, 48, 8, 1760],
  ["2026-03-02", 288, 33, 7, 1761],
  ["2026-03-03", 359, 56, 9, 1779],
  ["2026-03-04", 412, 74, 10, 1786],
  ["2026-03-05", 332, 49, 9, 1778],
  ["2026-03-06", 271, 28, 8, 1765],
  ["2026-03-07", 395, 67, 10, 1788],
  ["2026-03-08", 318, 50, 9, 1774]
] as const;

const activitySets: MeasurementSetSeed[] = activityDays.map(
  ([date, activeKcal, exerciseMinutes, standHours, restingKcal]) =>
    measurementSet(
      `activity-${date}`,
      "source-apple-health",
      "activity_daily",
      `Apple Health 活动 ${date}`,
      `${date}T21:00:00+08:00`,
      [
        measurement("activity.active_kcal", activeKcal, "kcal"),
        measurement("activity.exercise_minutes", exerciseMinutes, "min"),
        measurement("activity.stand_hours", standHours, "h"),
        measurement("activity.resting_kcal", restingKcal, "kcal")
      ],
      "来自 Apple Health 近两周 mock 日汇总样本。"
    )
);

const sleepDays = [
  ["2026-02-23", 438, 372],
  ["2026-02-24", 426, 361],
  ["2026-02-25", 441, 369],
  ["2026-02-26", 430, 358],
  ["2026-02-27", 452, 381],
  ["2026-02-28", 468, 392],
  ["2026-03-01", 421, 347],
  ["2026-03-02", 416, 341],
  ["2026-03-03", 433, 355],
  ["2026-03-04", 447, 367],
  ["2026-03-05", 439, 362],
  ["2026-03-06", 454, 377],
  ["2026-03-07", 428, 349],
  ["2026-03-08", 445, 371]
] as const;

const sleepSets: MeasurementSetSeed[] = sleepDays.map(([date, inBed, asleep]) =>
  measurementSet(
    `sleep-${date}`,
    "source-apple-health",
    "sleep_daily",
    `Apple Health 睡眠 ${date}`,
    `${date}T10:00:00+08:00`,
    [
      measurement("sleep.in_bed_minutes", inBed, "min"),
      measurement("sleep.asleep_minutes", asleep, "min")
    ],
    "来自 Apple Health 近两周 mock 睡眠样本。"
  )
);

export const measurementSets: MeasurementSetSeed[] = [
  ...annualExamSets,
  ...lipidPanelSets,
  ...bodyCompositionSets,
  ...activitySets,
  ...sleepSets
];

export const geneticFindings: GeneticFindingSeed[] = [
  {
    id: "gene-lpa-demo",
    sourceId: "source-gene-report",
    geneSymbol: "LPA",
    variantId: "rs3798220",
    traitCode: "lipid.lpa_background",
    riskLevel: "high",
    evidenceLevel: "A",
    summary: "演示位点提示可能存在较高的 Lp(a) 背景倾向，适合作为长期风险标签而非短期波动指标。",
    suggestion: "将 Lp(a) 作为慢变量，每 6-12 个月复查一次，并与 LDL-C 管理联动观察。",
    recordedAt: "2025-12-01T09:00:00+08:00",
    rawPayload: {
      isDemo: true,
      category: "lipid"
    }
  },
  {
    id: "gene-apoe-demo",
    sourceId: "source-gene-report",
    geneSymbol: "APOE",
    variantId: "rs429358",
    traitCode: "lipid.ldl_clearance_response",
    riskLevel: "medium",
    evidenceLevel: "B",
    summary: "演示位点提示 LDL-C 对饮食结构和恢复波动可能更敏感，适合作为解释同样干预下个体差异的背景因素。",
    suggestion: "把 LDL-C 与 ApoB 的复查节奏固定下来，重点观察饮食调整后的回落幅度是否稳定。",
    recordedAt: "2025-12-01T09:00:00+08:00",
    rawPayload: {
      isDemo: true,
      category: "lipid"
    }
  },
  {
    id: "gene-fto-demo",
    sourceId: "source-gene-report",
    geneSymbol: "FTO",
    variantId: "rs9939609",
    traitCode: "body.weight_regain_tendency",
    riskLevel: "medium",
    evidenceLevel: "B",
    summary: "演示位点提示体脂和食欲调节可能更容易在生活节奏波动时反弹，适合作为体重管理中的长期背景提示。",
    suggestion: "把体脂率、体重和训练执行度一起看，优先关注节假日或出差周期后的回弹幅度。",
    recordedAt: "2025-12-01T09:00:00+08:00",
    rawPayload: {
      isDemo: true,
      category: "body"
    }
  },
  {
    id: "gene-tcf7l2-demo",
    sourceId: "source-gene-report",
    geneSymbol: "TCF7L2",
    variantId: "rs7903146",
    traitCode: "glycemic.postprandial_response",
    riskLevel: "medium",
    evidenceLevel: "A",
    summary: "演示位点提示餐后血糖波动可能更值得关注，适合作为解释相同体重下降下代谢改善速度差异的背景信息。",
    suggestion: "如后续接入更多血糖或饮食记录，可优先观察晚餐后恢复速度与下一次复查的关系。",
    recordedAt: "2025-12-01T09:00:00+08:00",
    rawPayload: {
      isDemo: true,
      category: "glycemic"
    }
  },
  {
    id: "gene-caffeine-demo",
    sourceId: "source-gene-report",
    geneSymbol: "CYP1A2",
    variantId: "rs762551",
    traitCode: "sleep.caffeine_sensitivity",
    riskLevel: "medium",
    evidenceLevel: "B",
    summary: "演示位点提示咖啡因清除速度可能偏慢，适合作为睡眠恢复建议的个体化背景信息。",
    suggestion: "如后续导入真实基因结果，可结合睡眠数据评估晚间咖啡因摄入窗口。",
    recordedAt: "2025-12-01T09:00:00+08:00",
    rawPayload: {
      isDemo: true,
      category: "sleep"
    }
  },
  {
    id: "gene-ace-demo",
    sourceId: "source-gene-report",
    geneSymbol: "ACE",
    variantId: "rs4343",
    traitCode: "activity.endurance_response",
    riskLevel: "low",
    evidenceLevel: "C",
    summary: "演示位点提示更适合通过连续的训练执行度与恢复质量来观察耐力适应，而不是仅凭单次训练表现做判断。",
    suggestion: "把训练分钟、活动能量和睡眠恢复放在同一时间轴上看，判断当前训练安排是否可持续。",
    recordedAt: "2025-12-01T09:00:00+08:00",
    rawPayload: {
      isDemo: true,
      category: "activity"
    }
  }
];
