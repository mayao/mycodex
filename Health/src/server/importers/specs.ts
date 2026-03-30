import type { ImporterSpec } from "./types";

const commonReferences = {
  tc: { referenceHigh: 5.2, referenceRange: "<= 5.2 mmol/L" },
  tg: { referenceHigh: 1.7, referenceRange: "<= 1.7 mmol/L" },
  hdl: { referenceLow: 1.04, referenceRange: ">= 1.04 mmol/L" },
  ldl: { referenceHigh: 3.4, referenceRange: "<= 3.4 mmol/L" },
  apoa1: { referenceLow: 1.2, referenceHigh: 1.6, referenceRange: "1.2 - 1.6 g/L" },
  apob: { referenceLow: 0.8, referenceHigh: 1.1, referenceRange: "0.8 - 1.1 g/L" },
  lpa: { referenceHigh: 30, referenceRange: "<= 30 mg/dL" }
};

export const importerSpecs: Record<ImporterSpec["key"], ImporterSpec> = {
  annual_exam: {
    key: "annual_exam",
    sourceType: "annual_exam_tabular",
    sourceName: "年度体检表格导入",
    taskType: "annual_exam_import",
    sampleTimeAliases: ["sample_time", "日期", "体检日期", "检查日期"],
    noteAliases: ["notes", "备注"],
    fieldMappings: [
      {
        metricCode: "body.height_cm",
        metricName: "身高",
        category: "body_composition",
        aliases: ["身高", "height", "heightcm"],
        canonicalUnit: "cm",
        betterDirection: "neutral",
        description: "身高",
        defaultSourceUnit: "cm",
        normalizer: "height"
      },
      {
        metricCode: "body.weight",
        metricName: "体重",
        category: "body_composition",
        aliases: ["体重", "weight"],
        canonicalUnit: "kg",
        betterDirection: "down",
        description: "体重",
        defaultSourceUnit: "kg",
        referenceLow: 60.6,
        referenceHigh: 82,
        referenceRange: "60.6 - 82 kg",
        normalizer: "weight"
      },
      {
        metricCode: "body.bmi",
        metricName: "BMI",
        category: "body_composition",
        aliases: ["bmi"],
        canonicalUnit: "kg/m2",
        betterDirection: "down",
        description: "BMI",
        defaultSourceUnit: "kg/m2",
        referenceLow: 18.5,
        referenceHigh: 24.9,
        referenceRange: "18.5 - 24.9 kg/m2",
        normalizer: "identity"
      },
      {
        metricCode: "glycemic.glucose",
        metricName: "血糖",
        category: "lab",
        aliases: ["血糖", "glucose", "空腹血糖"],
        canonicalUnit: "mmol/L",
        betterDirection: "down",
        description: "血糖",
        defaultSourceUnit: "mmol/L",
        referenceLow: 3.9,
        referenceHigh: 6.09,
        referenceRange: "3.9 - 6.09 mmol/L",
        normalizer: "glucose"
      },
      {
        metricCode: "lipid.total_cholesterol",
        metricName: "总胆固醇",
        category: "lipid",
        aliases: ["总胆固醇", "tc", "totalcholesterol"],
        canonicalUnit: "mmol/L",
        betterDirection: "down",
        description: "总胆固醇",
        defaultSourceUnit: "mmol/L",
        ...commonReferences.tc,
        normalizer: "cholesterol"
      },
      {
        metricCode: "lipid.ldl_c",
        metricName: "低密度脂蛋白胆固醇",
        category: "lipid",
        aliases: ["ldl-c", "ldlc", "低密度脂蛋白胆固醇"],
        canonicalUnit: "mmol/L",
        betterDirection: "down",
        description: "低密度脂蛋白胆固醇",
        defaultSourceUnit: "mmol/L",
        ...commonReferences.ldl,
        normalizer: "cholesterol"
      },
      {
        metricCode: "renal.uric_acid",
        metricName: "尿酸",
        category: "lab",
        aliases: ["尿酸", "uricacid"],
        canonicalUnit: "umol/L",
        betterDirection: "down",
        description: "尿酸",
        defaultSourceUnit: "umol/L",
        referenceLow: 240,
        referenceHigh: 420,
        referenceRange: "240 - 420 umol/L",
        normalizer: "identity"
      }
    ]
  },
  blood_test: {
    key: "blood_test",
    sourceType: "blood_test_tabular",
    sourceName: "血液检查表格导入",
    taskType: "blood_test_import",
    sampleTimeAliases: ["sample_time", "日期", "采样日期", "检查日期"],
    noteAliases: ["notes", "备注"],
    fieldMappings: [
      {
        metricCode: "lipid.total_cholesterol",
        metricName: "总胆固醇",
        category: "lipid",
        aliases: ["总胆固醇", "tc", "totalcholesterol"],
        canonicalUnit: "mmol/L",
        betterDirection: "down",
        description: "总胆固醇",
        defaultSourceUnit: "mmol/L",
        ...commonReferences.tc,
        normalizer: "cholesterol"
      },
      {
        metricCode: "lipid.triglycerides",
        metricName: "甘油三酯",
        category: "lipid",
        aliases: ["甘油三酯", "tg", "triglycerides"],
        canonicalUnit: "mmol/L",
        betterDirection: "down",
        description: "甘油三酯",
        defaultSourceUnit: "mmol/L",
        ...commonReferences.tg,
        normalizer: "triglycerides"
      },
      {
        metricCode: "lipid.hdl_c",
        metricName: "高密度脂蛋白胆固醇",
        category: "lipid",
        aliases: ["高密度脂蛋白胆固醇", "hdl-c", "hdlc"],
        canonicalUnit: "mmol/L",
        betterDirection: "up",
        description: "高密度脂蛋白胆固醇",
        defaultSourceUnit: "mmol/L",
        ...commonReferences.hdl,
        normalizer: "cholesterol"
      },
      {
        metricCode: "lipid.ldl_c",
        metricName: "低密度脂蛋白胆固醇",
        category: "lipid",
        aliases: ["低密度脂蛋白胆固醇", "ldl-c", "ldlc"],
        canonicalUnit: "mmol/L",
        betterDirection: "down",
        description: "低密度脂蛋白胆固醇",
        defaultSourceUnit: "mmol/L",
        ...commonReferences.ldl,
        normalizer: "cholesterol"
      },
      {
        metricCode: "lipid.apoa1",
        metricName: "载脂蛋白A1",
        category: "lipid",
        aliases: ["载脂蛋白a1", "apoa1"],
        canonicalUnit: "g/L",
        betterDirection: "up",
        description: "载脂蛋白A1",
        defaultSourceUnit: "g/L",
        ...commonReferences.apoa1,
        normalizer: "identity"
      },
      {
        metricCode: "lipid.apob",
        metricName: "载脂蛋白B",
        category: "lipid",
        aliases: ["载脂蛋白b", "apob"],
        canonicalUnit: "g/L",
        betterDirection: "down",
        description: "载脂蛋白B",
        defaultSourceUnit: "g/L",
        ...commonReferences.apob,
        normalizer: "identity"
      },
      {
        metricCode: "lipid.lpa",
        metricName: "脂蛋白(a)",
        category: "lipid",
        aliases: ["脂蛋白(a)", "脂蛋白a", "lpa", "lp(a)"],
        canonicalUnit: "mg/dL",
        betterDirection: "down",
        description: "脂蛋白(a)",
        defaultSourceUnit: "mg/dL",
        ...commonReferences.lpa,
        normalizer: "identity"
      },
      {
        metricCode: "renal.creatinine",
        metricName: "肌酐",
        category: "lab",
        aliases: ["肌酐", "creatinine"],
        canonicalUnit: "umol/L",
        betterDirection: "down",
        description: "肌酐",
        defaultSourceUnit: "umol/L",
        referenceLow: 57,
        referenceHigh: 97,
        referenceRange: "57 - 97 umol/L",
        normalizer: "creatinine"
      }
    ]
  },
  body_scale: {
    key: "body_scale",
    sourceType: "body_scale_csv",
    sourceName: "体脂秤 CSV 导入",
    taskType: "body_scale_import",
    sampleTimeAliases: ["sample_time", "测量时间", "日期", "检测时间"],
    noteAliases: ["notes", "备注"],
    fieldMappings: [
      {
        metricCode: "body.weight",
        metricName: "体重",
        category: "body_composition",
        aliases: ["体重", "weight"],
        canonicalUnit: "kg",
        betterDirection: "down",
        description: "体重",
        defaultSourceUnit: "kg",
        referenceLow: 60.6,
        referenceHigh: 82,
        referenceRange: "60.6 - 82 kg",
        normalizer: "weight"
      },
      {
        metricCode: "body.body_fat_pct",
        metricName: "体脂率",
        category: "body_composition",
        aliases: ["体脂率", "bodyfat", "bodyfatpct"],
        canonicalUnit: "%",
        betterDirection: "down",
        description: "体脂率",
        defaultSourceUnit: "%",
        referenceLow: 10,
        referenceHigh: 20,
        referenceRange: "10 - 20 %",
        normalizer: "percentage"
      },
      {
        metricCode: "body.water_pct",
        metricName: "体水分",
        category: "body_composition",
        aliases: ["体水分", "water", "waterpct"],
        canonicalUnit: "%",
        betterDirection: "up",
        description: "体水分",
        defaultSourceUnit: "%",
        normalizer: "percentage"
      },
      {
        metricCode: "body.skeletal_muscle_pct",
        metricName: "骨骼肌率",
        category: "body_composition",
        aliases: ["骨骼肌率", "skeletalmuscle", "skeletalmusclepct"],
        canonicalUnit: "%",
        betterDirection: "up",
        description: "骨骼肌率",
        defaultSourceUnit: "%",
        normalizer: "percentage"
      },
      {
        metricCode: "body.visceral_fat_level",
        metricName: "内脏脂肪等级",
        category: "body_composition",
        aliases: ["内脏脂肪等级", "visceralfat", "visceralfatlevel"],
        canonicalUnit: "level",
        betterDirection: "down",
        description: "内脏脂肪等级",
        defaultSourceUnit: "level",
        referenceHigh: 9,
        referenceRange: "<= 9 level",
        normalizer: "identity"
      },
      {
        metricCode: "body.basal_metabolism",
        metricName: "基础代谢率",
        category: "body_composition",
        aliases: ["基础代谢率", "基础代谢", "basalmetabolism", "bmr"],
        canonicalUnit: "kcal",
        betterDirection: "neutral",
        description: "基础代谢率",
        defaultSourceUnit: "kcal",
        normalizer: "energy"
      }
    ]
  },
  activity: {
    key: "activity",
    sourceType: "activity_csv",
    sourceName: "运动 CSV 导入",
    taskType: "activity_import",
    sampleTimeAliases: ["sample_time", "日期", "date", "运动日期"],
    noteAliases: ["notes", "备注"],
    contextAliases: ["activity_type", "运动类型", "type"],
    fieldMappings: [
      {
        metricCode: "activity.exercise_minutes",
        metricName: "训练分钟",
        category: "activity",
        aliases: ["训练分钟", "duration", "durationmin", "时长", "时长分钟"],
        canonicalUnit: "min",
        betterDirection: "up",
        description: "训练分钟",
        defaultSourceUnit: "min",
        normalizer: "duration"
      },
      {
        metricCode: "activity.steps",
        metricName: "步数",
        category: "activity",
        aliases: ["步数", "steps"],
        canonicalUnit: "count",
        betterDirection: "up",
        description: "步数",
        defaultSourceUnit: "count",
        normalizer: "identity"
      },
      {
        metricCode: "activity.distance_km",
        metricName: "距离",
        category: "activity",
        aliases: ["距离", "distance", "distancekm"],
        canonicalUnit: "km",
        betterDirection: "up",
        description: "距离",
        defaultSourceUnit: "km",
        normalizer: "distance"
      },
      {
        metricCode: "activity.active_kcal",
        metricName: "活动能量",
        category: "activity",
        aliases: ["活动能量", "activekcal", "calories", "热量消耗"],
        canonicalUnit: "kcal",
        betterDirection: "up",
        description: "活动能量",
        defaultSourceUnit: "kcal",
        normalizer: "energy"
      },
      {
        metricCode: "activity.avg_heart_rate",
        metricName: "平均心率",
        category: "activity",
        aliases: ["平均心率", "avghr", "averageheartrate"],
        canonicalUnit: "bpm",
        betterDirection: "neutral",
        description: "平均心率",
        defaultSourceUnit: "bpm",
        normalizer: "heart_rate"
      }
    ]
  },
  genetic: {
    key: "genetic",
    sourceType: "genetic_report",
    sourceName: "基因报告导入",
    taskType: "genetic_import",
    sampleTimeAliases: ["sample_time", "日期", "检测日期"],
    noteAliases: ["notes", "备注"],
    fieldMappings: []
  },
  diet: {
    key: "diet",
    sourceType: "diet_image",
    sourceName: "饮食健康导入",
    taskType: "diet_import",
    sampleTimeAliases: ["sample_time", "日期", "记录日期", "upload_date"],
    noteAliases: ["notes", "备注", "食物", "foods"],
    fieldMappings: [
      {
        metricCode: "diet.calories_intake_kcal",
        metricName: "摄入热量",
        category: "diet",
        aliases: ["摄入热量", "热量", "总热量", "calories", "calories_intake_kcal", "kcal"],
        canonicalUnit: "kcal",
        betterDirection: "neutral",
        description: "当日饮食总热量（同日多次上传按餐次累加）。",
        defaultSourceUnit: "kcal",
        normalizer: "energy"
      },
      {
        metricCode: "diet.meal_upload_count",
        metricName: "饮食记录次数",
        category: "diet",
        aliases: ["饮食记录次数", "餐次上传次数", "meal_upload_count", "meal_count", "upload_count"],
        canonicalUnit: "count",
        betterDirection: "up",
        description: "当日饮食上传次数，用于评估记录覆盖率。",
        defaultSourceUnit: "count",
        normalizer: "identity"
      }
    ]
  }
};
