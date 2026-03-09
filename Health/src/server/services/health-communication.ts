interface EducationalCopy {
  meaning?: string;
  practicalAdvice?: string;
}

const metricCopy: Record<string, EducationalCopy> = {
  "lipid.ldl_c": {
    meaning: "LDL-C 是常说的“坏胆固醇”核心观察项，用来看低密度脂蛋白带来的血脂负担。",
    practicalAdvice: "把晚餐油脂结构、每周有氧加力量训练、8-12 周后复查 LDL-C 放到同一跟踪节奏里。"
  },
  "lipid.total_cholesterol": {
    meaning: "TC 是总胆固醇，反映整体血脂水平，但要结合 LDL-C、HDL-C 和甘油三酯一起看。",
    practicalAdvice: "减少高饱和脂肪和夜宵型进食，保留复查前 6-8 周相对稳定的作息和运动节奏。"
  },
  "lipid.hdl_c": {
    meaning: "HDL-C 常被称为“好胆固醇”，更适合结合运动、体重和甘油三酯一起评估代谢状态。",
    practicalAdvice: "优先保证每周稳定运动、控制体脂和规律睡眠，不需要只盯某一次 HDL-C 数值。"
  },
  "lipid.triglycerides": {
    meaning: "甘油三酯更容易受饮食、饮酒、体重和运动影响，适合观察近期生活方式变化。",
    practicalAdvice: "先看近 2 周晚餐碳水、酒精、零食和活动量，再决定是否提前安排复查。"
  },
  "lipid.lpa": {
    meaning: "Lp(a) 更像先天背景型血脂指标，短期生活方式不一定明显改变，但会影响长期风险分层。",
    practicalAdvice: "把它当作慢变量，每 6-12 个月复查看一次，并把长期重点放在 LDL-C 管理和生活方式稳定性上。"
  },
  "lipid.apob": {
    meaning: "载脂蛋白 B 反映动脉粥样硬化相关颗粒数量，比只看总胆固醇更接近颗粒负担。",
    practicalAdvice: "结合 LDL-C、甘油三酯、体脂率一起看，不要单独解读一次 ApoB 波动；按下一次血脂复查继续追踪。"
  },
  "body.weight": {
    meaning: "体重反映总体负荷，最好和体脂率、腰围、训练量一起看，避免只盯体重数字。",
    practicalAdvice: "优先记录每周平均体重和腰围，再结合力量训练和蛋白质摄入判断变化质量。"
  },
  "body.body_fat_pct": {
    meaning: "体脂率比体重更接近脂肪占比，用来区分是减脂、增肌还是短期水分波动。",
    practicalAdvice: "把体脂率和训练分钟、步数、腰围放在同一周维度看，先确认趋势是否连续 2-4 周。"
  },
  "body.bmi": {
    meaning: "BMI 是体重与身高的比值，用来快速判断总体体重负荷，但不能区分脂肪和肌肉。",
    practicalAdvice: "把 BMI 当筛查信号，再结合体脂率、腰围和力量训练情况判断是否真的需要进一步减脂。"
  },
  "glycemic.glucose": {
    meaning: "血糖用于观察葡萄糖代谢状态，通常要结合空腹状态、体重变化和后续复查一起判断。",
    practicalAdvice: "先把晚餐时间、餐后步行、体重趋势和下次空腹复查放在一起看，不建议只看单次血糖。"
  },
  "renal.creatinine": {
    meaning: "肌酐常用来观察肾功能和肌肉代谢背景，饮水、肌肉量和采血前运动也会影响结果。",
    practicalAdvice: "复查前注意补水，避免剧烈训练后立刻抽血，并和 eGFR、尿酸一起看更稳妥。"
  },
  "renal.egfr": {
    meaning: "eGFR 是估算肾小球滤过率，用来粗略反映肾脏过滤能力，通常和肌酐一起看。",
    practicalAdvice: "先保证补水和规律作息，再按下次肾功能复查确认是否持续偏低，不要只根据一次结果放大解读。"
  },
  "activity.exercise_minutes": {
    meaning: "训练分钟反映最近的运动执行度，是解释体脂、睡眠和血脂变化的重要行为信号。",
    practicalAdvice: "把目标定在稳定可持续的周训练量，而不是几天冲高后又中断。"
  }
};

function containsKeyword(value: string | undefined, keywords: string[]): boolean {
  if (!value) {
    return false;
  }

  return keywords.some((keyword) => value.includes(keyword));
}

export function getMetricEducationalCopy(metricCode: string | undefined): EducationalCopy | undefined {
  if (!metricCode) {
    return undefined;
  }

  return metricCopy[metricCode];
}

export function getAnnualExamEducationalCopy(): EducationalCopy {
  return {
    meaning:
      "BMI 反映总体体重负荷，TC 和 LDL-C 反映血脂负担，这几项一起看更能说明代谢管理压力。",
    practicalAdvice:
      "先把每周体重/腰围、晚餐结构、训练频率和 8-12 周后的血脂复查放到同一执行计划里。"
  };
}

export function getGeneticEducationalCopy(traitLabel: string | undefined, title?: string): EducationalCopy | undefined {
  if (containsKeyword(traitLabel, ["Lp(a)"]) || containsKeyword(title, ["Lp(a)"])) {
    return {
      meaning:
        "这类基因提示更像长期背景，不代表短期一定出问题，但会影响你对血脂和长期风险的解释方式。",
      practicalAdvice:
        "把它作为长期标签保留，重点仍放在 LDL-C、体脂率和复查节奏这些可执行、可跟踪的项目上。"
    };
  }

  if (containsKeyword(traitLabel, ["咖啡因"]) || containsKeyword(title, ["咖啡因"])) {
    return {
      meaning:
        "它反映你对咖啡因的清除速度，主要影响晚间入睡、睡眠连续性和第二天恢复感受。",
      practicalAdvice:
        "先把咖啡、浓茶或能量饮料截止时间提前到中午后，再看 2-3 周睡眠和恢复记录是否改善。"
    };
  }

  return undefined;
}

export function getInsightEducationalCopy(input: {
  id: string;
  title: string;
  metricCode?: string;
}): EducationalCopy | undefined {
  if (input.id.startsWith("doc::annual-exam")) {
    return getAnnualExamEducationalCopy();
  }

  if (input.id.startsWith("doc::genetic")) {
    return getGeneticEducationalCopy(undefined, input.title);
  }

  return getMetricEducationalCopy(input.metricCode);
}
