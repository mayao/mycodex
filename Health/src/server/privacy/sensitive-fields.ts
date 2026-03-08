import { normalizeHeader } from "../importers/header-utils";

export type SensitiveFieldCategory =
  | "identity"
  | "demographic"
  | "health_metric"
  | "sample_time"
  | "free_text"
  | "file_metadata"
  | "context"
  | "unclassified";

export interface SensitiveFieldDescriptor {
  category: SensitiveFieldCategory;
  label: string;
  description: string;
  examples: string[];
  storageRule: string;
}

export const sensitiveFieldCatalog: SensitiveFieldDescriptor[] = [
  {
    category: "identity",
    label: "身份标识字段",
    description: "可直接识别个人身份或账号归属的字段。",
    examples: ["user_id", "姓名", "昵称", "手机号", "邮箱"],
    storageRule: "不进入普通日志，排查时只保留字段名与脱敏标签。"
  },
  {
    category: "demographic",
    label: "人口学字段",
    description: "可用于缩小身份范围的背景属性。",
    examples: ["出生年份", "年龄", "性别", "地址"],
    storageRule: "默认不写入审计日志值，仅在结构化数据库中按最小必要原则保存。"
  },
  {
    category: "health_metric",
    label: "健康指标字段",
    description: "原始健康测量值与检查结果。",
    examples: ["血糖", "LDL-C", "体重", "体脂率", "心率"],
    storageRule: "业务表保留结构化值，导入行日志仅保留脱敏占位。"
  },
  {
    category: "sample_time",
    label: "采样时间字段",
    description: "可关联健康事件发生时间的日期与时间字段。",
    examples: ["日期", "采样日期", "测量时间"],
    storageRule: "导入行日志不保留原始时间值，仅记录脱敏标签。"
  },
  {
    category: "free_text",
    label: "自由文本字段",
    description: "备注、说明、医生意见等无法预测内容的字段。",
    examples: ["备注", "notes", "说明"],
    storageRule: "默认视为高敏感文本，不写入普通日志明文。"
  },
  {
    category: "file_metadata",
    label: "文件元数据",
    description: "来源文件名、路径等可能隐含身份或机构信息的字段。",
    examples: ["source_file", "file_name", "path"],
    storageRule: "仅保存最小必要元数据，日志中避免输出完整路径。"
  },
  {
    category: "context",
    label: "上下文字段",
    description: "运动类型、场景说明等补充语义字段，仍可能构成个人行为画像。",
    examples: ["运动类型", "context", "来源描述"],
    storageRule: "审计日志中只保留字段名和脱敏标签。"
  },
  {
    category: "unclassified",
    label: "未分类字段",
    description: "未知自定义列，默认按保守策略处理。",
    examples: ["自定义字段", "未知字段"],
    storageRule: "无法确定安全级别时默认脱敏。"
  }
];

const categoryKeywords: Array<{
  category: Exclude<SensitiveFieldCategory, "health_metric" | "context" | "unclassified">;
  keywords: string[];
}> = [
  {
    category: "identity",
    keywords: [
      "userid",
      "user_id",
      "username",
      "name",
      "displayname",
      "nickname",
      "email",
      "mail",
      "phone",
      "mobile",
      "idcard",
      "身份证",
      "姓名",
      "昵称",
      "邮箱",
      "电话",
      "手机号"
    ]
  },
  {
    category: "demographic",
    keywords: ["birth", "birthday", "age", "gender", "sex", "address", "出生", "年龄", "性别", "地址"]
  },
  {
    category: "sample_time",
    keywords: ["date", "time", "datetime", "timestamp", "日期", "时间", "采样", "测量时间"]
  },
  {
    category: "free_text",
    keywords: ["note", "notes", "comment", "remark", "memo", "备注", "说明", "意见"]
  },
  {
    category: "file_metadata",
    keywords: ["file", "filename", "filepath", "path", "sourcefile", "source_file"]
  }
];

export function classifySensitiveHeader(header: string): SensitiveFieldCategory | undefined {
  const normalized = normalizeHeader(header);

  for (const rule of categoryKeywords) {
    if (rule.keywords.some((keyword) => normalized.includes(normalizeHeader(keyword)))) {
      return rule.category;
    }
  }

  return undefined;
}

export function formatRedactionLabel(category: SensitiveFieldCategory): string {
  return `[REDACTED:${category}]`;
}
