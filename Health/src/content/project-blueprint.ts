export const techChoices = [
  {
    area: "前端",
    selection: "Next.js App Router + React 19 + TypeScript",
    reason: "单体 Web 应用即可覆盖页面、API 和服务层，减少首版系统复杂度。"
  },
  {
    area: "后端",
    selection: "Next.js Server Components + Route Handlers",
    reason: "首版不拆独立服务，保留未来抽离 API 服务的空间。"
  },
  {
    area: "数据库",
    selection: "SQLite（Node 内置 node:sqlite）",
    reason: "local-first、单用户、零额外数据库依赖，适合敏感健康数据默认本地存储。"
  },
  {
    area: "图表",
    selection: "Recharts",
    reason: "成熟稳定，足以覆盖趋势折线图、双轴图和后续周报图表。"
  },
  {
    area: "校验",
    selection: "TypeScript + 领域类型 + 可扩展到 Zod",
    reason: "先保证 schema 与服务层边界清晰，再在导入阶段加强输入校验。"
  },
  {
    area: "测试",
    selection: "Node test runner + tsx",
    reason: "依赖少，适合首版服务层和规则层的基础测试。"
  }
];

export const directoryTree = `.
├── README.md
├── data/                          # 运行时生成的本地 SQLite 文件
├── docs/
│   └── mock-data-design.md
├── scripts/
│   └── inspect-db.ts
├── src/
│   ├── app/
│   │   ├── api/dashboard/route.ts
│   │   ├── globals.css
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── components/
│   │   ├── section-card.tsx
│   │   └── trend-chart.tsx
│   ├── content/
│   │   └── project-blueprint.ts
│   ├── data/mock/
│   │   └── seed-data.ts
│   └── server/
│       ├── db/
│       │   ├── schema.ts
│       │   ├── seed.ts
│       │   └── sqlite.ts
│       ├── domain/
│       │   └── types.ts
│       ├── insights/
│       │   ├── rules.ts
│       │   └── rules.test.ts
│       ├── repositories/
│       │   └── health-repository.ts
│       └── services/
│           ├── dashboard-service.ts
│           └── dashboard-service.test.ts
├── eslint.config.mjs
├── next.config.ts
├── package.json
└── tsconfig.json`;

export const schemaBlueprint = [
  {
    table: "users",
    purpose: "单用户优先，但保留未来扩展多成员档案的能力。"
  },
  {
    table: "data_sources",
    purpose: "统一记录 PDF、手工录入、设备 App、可穿戴等来源。"
  },
  {
    table: "measurement_sets",
    purpose: "把一次体检、一张血脂复查、一日睡眠汇总视为一个观测集合。"
  },
  {
    table: "measurements",
    purpose: "以指标明细为粒度保存原始值、标准化值、单位、参考范围和异常标记。"
  },
  {
    table: "metric_catalog",
    purpose: "沉淀统一 metric code，支撑后续导入映射和规则引擎。"
  },
  {
    table: "genetic_findings",
    purpose: "基因检测用 finding 结构独立建表，避免和连续数值型指标混用。"
  },
  {
    table: "rule_events/report_snapshots",
    purpose: "为后续规则提醒、周报、月报和快照归档预留扩展位。"
  }
];

export const roadmapPhases = [
  {
    phase: "MVP",
    goal: "本地单用户 dashboard + SQLite schema + mock 数据 + 基础规则洞察",
    output: "先打通页面、数据层、规则层和 README。"
  },
  {
    phase: "V1",
    goal: "真实文件导入（体检 PDF / 血脂复查 / 体脂秤 CSV 或截图转录）",
    output: "形成可复用的导入映射、人工校对和异常数据处理流程。"
  },
  {
    phase: "V2",
    goal: "周报/月报、更多健康模块、规则引擎配置化、LLM 洞察编排",
    output: "在规则摘要基础上生成更完整的经营视图和行动建议。"
  }
];

export const phaseOneCompleted = [
  "完成 Next.js Web 骨架和首页 dashboard。",
  "落地 SQLite schema，并在运行时自动初始化本地数据库。",
  "提供体检、血脂、体脂秤、活动、睡眠、基因 finding 的 mock 数据。",
  "提供基础规则洞察与非医疗诊断免责声明。",
  "提供 README、mock 数据设计文档和基础测试。"
];

export const phaseOnePending = [
  "真实 PDF / 图片 / CSV 导入管线尚未实现。",
  "规则引擎仍是代码内规则，尚未配置化。",
  "尚未接入睡眠阶段、心率、药物、饮食、家族史等扩展模块。",
  "尚未实现周报、月报和数据校对后台。"
];

export const nextStepRecommendation =
  "下一步最合理任务是实现真实导入管线：先做“血脂专项 PDF/手工录入 -> measurement_sets + measurements”的半自动导入流程。";
