import crypto from "node:crypto";
import http from "node:http";

const host = "0.0.0.0";
const port = Number(process.env.PORT || 3001);

const now = new Date().toISOString();

const user = {
  id: "user-self",
  displayName: "HealthAI Demo User",
  phoneNumber: "13800000001",
};

const basePrompt = {
  templateId: "healthai-cn-v1",
  version: "2026-03-13",
  systemPrompt: "你是 HealthAI 的健康摘要引擎。",
  userPrompt: "结合体脂、血脂、运动和睡眠数据输出结构化摘要。",
};

const latestNarrative = {
  provider: "mock",
  model: "healthai-chat-fallback-v1",
  prompt: basePrompt,
  output: {
    periodKind: "day",
    headline: "整体趋势偏积极，下一步把恢复节奏稳定下来。",
    mostImportantChanges: [
      "LDL-C 与体脂率继续回落。",
      "训练执行度保持稳定，但睡眠波动仍会影响恢复。",
    ],
    possibleReasons: [
      "近期训练频次与饮食结构较稳定。",
      "工作日晚睡仍在拉低恢复质量。",
    ],
    priorityActions: [
      "工作日把入睡时间前移 30 分钟。",
      "维持当前力量训练和中等强度有氧节奏。",
    ],
    continueObserving: [
      "持续跟踪睡眠时长和主观恢复感。",
      "Lp(a) 作为慢变量长期观察即可。",
    ],
    disclaimer: "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理。",
  },
};

function metricSummary(metricCode, metricName, unit, latestValue, abnormalFlag, trendDirection) {
  return {
    metricCode,
    metricName,
    category: metricCode.split(".")[0],
    unit,
    sampleCount: 8,
    latestValue,
    latestSampleTime: now,
    historicalMean: latestValue,
    latestVsMean: 0,
    latestVsMeanPct: 0,
    trendDirection,
    monthOverMonth: 0,
    yearOverYear: 0,
    abnormalFlag,
    referenceRange: null,
  };
}

function insight(id, title, severity, metricCode, metricName, unit, latestValue, summary, suggestedAction) {
  return {
    id,
    kind: "trend",
    title,
    severity,
    evidence: {
      summary,
      metrics: [
        {
          metricCode,
          metricName,
          unit,
          latestValue,
          latestSampleTime: now,
          sampleCount: 8,
          historicalMean: latestValue,
          latestVsMean: 0,
          latestVsMeanPct: 0,
          trendDirection: "stable",
          monthOverMonth: 0,
          yearOverYear: 0,
          abnormalFlag: "normal",
          referenceRange: null,
          relatedRecordIds: [`record-${id}`],
        },
      ],
    },
    possibleReason: "近期作息和训练执行度对趋势产生了直接影响。",
    suggestedAction,
    disclaimer: "用于健康管理提示，不替代临床判断。",
  };
}

const weeklyReport = {
  id: "weekly-2026-03-13",
  reportType: "weekly",
  periodStart: "2026-03-07",
  periodEnd: "2026-03-13",
  createdAt: now,
  title: "周报 | 代谢与恢复联动",
  summary: latestNarrative,
  structuredInsights: {
    generatedAt: now,
    userId: user.id,
    metricSummaries: [
      metricSummary("lipid.ldl_c", "LDL-C", "mmol/L", 2.82, "normal", "down"),
      metricSummary("body.body_fat_pct", "体脂率", "%", 20.8, "normal", "down"),
      metricSummary("activity.exercise_minutes", "训练分钟", "min", 56, "normal", "up"),
      metricSummary("sleep.asleep_minutes", "睡眠时长", "min", 425, "normal", "stable"),
    ],
    insights: [
      insight(
        "weekly-lipid",
        "血脂主线继续改善",
        "positive",
        "lipid.ldl_c",
        "LDL-C",
        "mmol/L",
        2.82,
        "LDL-C 继续回落，近期干预方向有效。",
        "保持当前饮食结构与训练节奏。"
      ),
      insight(
        "weekly-sleep",
        "恢复窗口仍可再拉长",
        "medium",
        "sleep.asleep_minutes",
        "睡眠时长",
        "min",
        425,
        "睡眠稳定性仍是当前最值得优化的变量。",
        "优先把工作日入睡时间再前移 30 分钟。"
      ),
    ],
  },
};

const monthlyReport = {
  ...weeklyReport,
  id: "monthly-2026-03",
  reportType: "monthly",
  periodStart: "2026-03-01",
  periodEnd: "2026-03-13",
  title: "月报 | 三月阶段性健康画像",
};

const reports = [weeklyReport, monthlyReport];

const dashboard = {
  generatedAt: now,
  disclaimer: "非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理。",
  overviewHeadline: "当前主线是延续代谢改善，同时把恢复节奏再拉稳一些。",
  overviewNarrative: "这个 LAN mock 服务返回的是 iOS App 可直接消费的结构化数据，用于验证手机端联调链路。",
  overviewDigest: {
    headline: "整体趋势偏积极",
    summary: "血脂和体脂在改善，训练执行稳定，恢复仍有优化空间。",
    goodSignals: ["LDL-C 稳步回落", "体脂率持续下降", "训练频率稳定"],
    needsAttention: ["工作日晚睡会拉低恢复质量"],
    longTermRisks: ["Lp(a) 继续作为慢变量长期观察"],
    actionPlan: ["固定入睡时间", "继续力量训练", "保持减脂节奏"],
  },
  overviewFocusAreas: ["血脂回落", "体脂优化", "训练执行", "睡眠恢复"],
  overviewSpotlights: [
    { label: "LDL-C", value: "2.82 mmol/L", tone: "positive", detail: "较基线继续下降" },
    { label: "体脂率", value: "20.8%", tone: "positive", detail: "连续数周改善" },
    { label: "训练分钟", value: "56 min", tone: "neutral", detail: "执行度保持稳定" },
    { label: "恢复状态", value: "7.1 h", tone: "attention", detail: "需要更稳定的作息" },
  ],
  sourceDimensions: [
    { key: "annual_exam", label: "年度体检", latestAt: "2025-12-18", status: "ready", summary: "作为长期基线。", highlight: "3 项持续跟踪" },
    { key: "lipid", label: "血脂专项", latestAt: "2026-03-09", status: "ready", summary: "LDL-C 与 ApoB 继续改善。", highlight: "LDL-C 2.82 mmol/L" },
    { key: "body", label: "体脂趋势", latestAt: "2026-03-10", status: "ready", summary: "体重与体脂率同向改善。", highlight: "20.8%" },
    { key: "activity", label: "运动执行度", latestAt: "2026-03-10", status: "ready", summary: "训练分钟维持中高位。", highlight: "56 min" },
  ],
  dimensionAnalyses: [
    {
      key: "integrated",
      kicker: "综合判断",
      title: "把代谢改善与恢复节奏放在同一张图里看",
      summary: "当前的核心不是继续加码，而是把有效动作保持住，并减少恢复端的波动。",
      goodSignals: ["代谢指标持续改善", "训练频率没有断档"],
      needsAttention: ["恢复节奏仍会被晚睡打断"],
      longTermRisks: ["慢变量仍需长期管理"],
      actionPlan: ["把入睡时间前移", "维持力量训练", "继续跟踪周报"],
      metrics: [
        { label: "LDL-C", value: "2.82 mmol/L", detail: "较基线下降", tone: "positive" },
        { label: "睡眠", value: "7.1 h", detail: "需要更稳定", tone: "attention" },
      ],
    },
  ],
  importOptions: [
    { key: "annual_exam", title: "年度体检", description: "导入体检结果。", formats: ["csv", "xlsx"], hints: ["支持模板导入"] },
    { key: "blood_test", title: "血液专项", description: "导入血脂和生化结果。", formats: ["csv", "xlsx"], hints: ["支持字段映射"] },
    { key: "body_scale", title: "体脂秤", description: "导入体重和体脂数据。", formats: ["csv"], hints: ["连续趋势更直观"] },
    { key: "activity", title: "运动", description: "导入运动与能量消耗。", formats: ["csv"], hints: ["支持 Apple Health 导出"] },
  ],
  overviewCards: [
    { metricCode: "lipid.ldl_c", label: "LDL-C", value: "2.82 mmol/L", trend: "继续下降", status: "improving", abnormalFlag: "normal", meaning: "血脂关键指标" },
    { metricCode: "body.body_fat_pct", label: "体脂率", value: "20.8 %", trend: "持续改善", status: "improving", abnormalFlag: "normal", meaning: "减脂质量" },
    { metricCode: "activity.exercise_minutes", label: "训练分钟", value: "56 min", trend: "稳定执行", status: "stable", abnormalFlag: "normal", meaning: "运动执行度" },
    { metricCode: "sleep.asleep_minutes", label: "睡眠", value: "425 min", trend: "略有波动", status: "watch", abnormalFlag: "normal", meaning: "恢复质量" },
  ],
  annualExam: null,
  geneticFindings: [],
  keyReminders: [
    {
      id: "reminder-sleep",
      title: "先把恢复节奏拉稳",
      severity: "medium",
      summary: "训练方向没问题，但恢复端仍在稀释收益。",
      suggestedAction: "工作日尽量提前 30 分钟入睡。",
      indicatorMeaning: "恢复质量会直接影响训练收益和主观状态。",
      practicalAdvice: "下午晚些时候减少咖啡因和高刺激内容。",
    },
  ],
  watchItems: [],
  latestNarrative,
  charts: {
    lipid: {
      title: "血脂趋势",
      description: "LDL-C 与 Lp(a) 的阶段变化",
      defaultRange: "90d",
      data: [
        { date: "2026-02-01", ldl: 3.22, lpa: 48 },
        { date: "2026-02-20", ldl: 2.96, lpa: 47 },
        { date: "2026-03-09", ldl: 2.82, lpa: 47 },
      ],
      lines: [
        { key: "ldl", label: "LDL-C", color: "#0f766e", unit: "mmol/L", yAxisId: "left" },
        { key: "lpa", label: "Lp(a)", color: "#5b21b6", unit: "mg/dL", yAxisId: "right" },
      ],
    },
    bodyComposition: {
      title: "体重 / 体脂趋势",
      description: "观察减脂质量而不只看体重。",
      defaultRange: "90d",
      data: [
        { date: "2026-02-01", weight: 80.1, bodyFat: 22.3 },
        { date: "2026-02-20", weight: 79.2, bodyFat: 21.4 },
        { date: "2026-03-10", weight: 78.4, bodyFat: 20.8 },
      ],
      lines: [
        { key: "weight", label: "体重", color: "#0f4c81", unit: "kg", yAxisId: "left" },
        { key: "bodyFat", label: "体脂率", color: "#be123c", unit: "%", yAxisId: "right" },
      ],
    },
    activity: {
      title: "运动执行",
      description: "训练分钟与活动能量。",
      defaultRange: "30d",
      data: [
        { date: "2026-03-08", exerciseMinutes: 48, activeKcal: 560 },
        { date: "2026-03-09", exerciseMinutes: 56, activeKcal: 640 },
        { date: "2026-03-10", exerciseMinutes: 61, activeKcal: 705 },
      ],
      lines: [
        { key: "exerciseMinutes", label: "训练分钟", color: "#0f766e", unit: "min", yAxisId: "left" },
        { key: "activeKcal", label: "活动能量", color: "#c2410c", unit: "kcal", yAxisId: "right" },
      ],
    },
    recovery: {
      title: "恢复趋势",
      description: "睡眠与训练关系。",
      defaultRange: "30d",
      data: [
        { date: "2026-03-08", sleepMinutes: 412, exerciseMinutes: 48 },
        { date: "2026-03-09", sleepMinutes: 436, exerciseMinutes: 56 },
        { date: "2026-03-10", sleepMinutes: 425, exerciseMinutes: 61 },
      ],
      lines: [
        { key: "sleepMinutes", label: "睡眠", color: "#1d4ed8", unit: "min", yAxisId: "left" },
        { key: "exerciseMinutes", label: "训练分钟", color: "#0f766e", unit: "min", yAxisId: "right" },
      ],
    },
  },
  latestReports: reports,
};

const importTasks = [
  {
    importTaskId: "task-demo-1",
    title: "体脂秤导入",
    importerKey: "body_scale",
    taskType: "body_scale_import",
    taskStatus: "completed",
    sourceType: "body_scale_tabular",
    sourceFile: "body_scale_sample.csv",
    startedAt: "2026-03-13T09:30:00.000Z",
    finishedAt: "2026-03-13T09:30:08.000Z",
    totalRecords: 18,
    successRecords: 18,
    failedRecords: 0,
    parseMode: "tabular",
  },
];

const deviceStatus = {
  devices: [
    { provider: "apple_health", label: "Apple 健康", isConnected: false, isConfigured: true, connectedAt: null, lastSyncAt: null },
    { provider: "garmin", label: "Garmin", isConnected: false, isConfigured: false, connectedAt: null, lastSyncAt: null },
  ],
};

let healthSuggestions = [
  {
    id: "suggestion-1",
    batchId: "batch-1",
    dimension: "sleep",
    title: "工作日固定入睡时间",
    description: "连续 7 天将入睡时间控制在 23:30 前，先稳定恢复质量。",
    targetMetricCode: "sleep.asleep_minutes",
    targetValue: 450,
    targetUnit: "min",
    frequency: "daily",
    timeHint: "23:00",
    priority: 1,
    createdAt: now,
  },
  {
    id: "suggestion-2",
    batchId: "batch-1",
    dimension: "exercise",
    title: "维持每周 4 次训练",
    description: "继续保留力量训练与中等强度有氧的组合。",
    targetMetricCode: "activity.exercise_minutes",
    targetValue: 50,
    targetUnit: "min",
    frequency: "weekly",
    timeHint: "19:00",
    priority: 2,
    createdAt: now,
  },
];

let healthPlanItems = [
  {
    id: "plan-1",
    userId: user.id,
    suggestionId: "seed-plan",
    dimension: "sleep",
    title: "固定工作日睡眠窗口",
    description: "尽量在 23:30 前入睡，连续一周观察第二天精神状态。",
    targetMetricCode: "sleep.asleep_minutes",
    targetValue: 450,
    targetUnit: "min",
    frequency: "daily",
    timeHint: "23:00",
    status: "active",
    createdAt: now,
    updatedAt: now,
  },
];

let healthPlanChecks = [
  {
    id: "check-1",
    planItemId: "plan-1",
    checkDate: now.slice(0, 10),
    actualValue: 1,
    isCompleted: 1,
    source: "manual",
    createdAt: now,
  },
];

const sessions = new Map();

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  res.end(body);
}

function htmlResponse(res, statusCode, body) {
  res.writeHead(statusCode, { "Content-Type": "text/html; charset=utf-8" });
  res.end(body);
}

function unauthorized(res, message = "未登录或会话已过期。") {
  json(res, 401, { error: { id: "unauthorized", message } });
}

function notFound(res, message = "接口不存在。") {
  json(res, 404, { error: { id: "not_found", message } });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function parseJson(text) {
  if (!text) {
    return {};
  }

  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function tokenFromRequest(req) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith("Bearer ")) {
    return null;
  }
  return auth.slice(7);
}

function requireUser(req, res) {
  const token = tokenFromRequest(req);
  if (!token || !sessions.has(token)) {
    unauthorized(res);
    return null;
  }
  return sessions.get(token);
}

function createToken(deviceId) {
  return crypto.createHash("sha256").update(`health-lan:${deviceId}`).digest("hex");
}

function buildPlanStats() {
  const activeItems = healthPlanItems.filter((item) => item.status === "active");
  const today = new Date().toISOString().slice(0, 10);
  const todayChecks = healthPlanChecks.filter((item) => item.checkDate.startsWith(today));
  const todayCompleted = todayChecks.filter((item) => item.isCompleted !== 0).length;
  const todayTotal = activeItems.length;
  const weekCompletionRate = todayTotal === 0 ? 0 : Math.min(1, todayCompleted / todayTotal);

  return {
    activeCount: activeItems.length,
    todayCompleted,
    todayTotal,
    weekCompletionRate,
  };
}

function buildPlanDashboard() {
  return {
    planItems: healthPlanItems.filter((item) => item.status === "active"),
    pausedItems: healthPlanItems.filter((item) => item.status === "paused"),
    suggestions: healthSuggestions,
    todayChecks: healthPlanChecks,
    stats: buildPlanStats(),
  };
}

const html = `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>HealthAI LAN Backend</title>
    <style>
      :root {
        color-scheme: light;
        --bg: #f5f1e8;
        --card: #fffdf8;
        --ink: #1f2937;
        --accent: #0f766e;
        --line: #d6d3d1;
      }
      body {
        margin: 0;
        font-family: "Avenir Next", "PingFang SC", sans-serif;
        background:
          radial-gradient(circle at top right, rgba(15,118,110,0.12), transparent 32%),
          linear-gradient(180deg, #fcfbf7 0%, var(--bg) 100%);
        color: var(--ink);
      }
      main {
        max-width: 820px;
        margin: 0 auto;
        padding: 40px 20px 72px;
      }
      .card {
        background: var(--card);
        border: 1px solid var(--line);
        border-radius: 24px;
        padding: 28px;
        box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
      }
      h1 {
        margin: 0 0 12px;
        font-size: 32px;
      }
      p, li {
        line-height: 1.7;
      }
      .pill {
        display: inline-block;
        margin-bottom: 16px;
        padding: 6px 10px;
        border-radius: 999px;
        background: rgba(15,118,110,0.1);
        color: var(--accent);
        font-size: 13px;
        font-weight: 600;
      }
      code {
        background: #f1f5f9;
        border-radius: 8px;
        padding: 2px 6px;
      }
    </style>
  </head>
  <body>
    <main>
      <section class="card">
        <span class="pill">HealthAI App Backend Ready</span>
        <h1>手机端 APP 联调服务已启动</h1>
        <p>这个 LAN mock backend 会返回 iOS App 需要的登录、首页、报告、数据和 AI 对话接口。</p>
        <ul>
          <li><code>/api/auth/device-login</code></li>
          <li><code>/api/auth/me</code></li>
          <li><code>/api/dashboard</code></li>
          <li><code>/api/reports</code></li>
          <li><code>/api/ai/chat</code></li>
          <li><code>/api/devices/status</code></li>
        </ul>
      </section>
    </main>
  </body>
</html>`;

const server = http.createServer(async (req, res) => {
  if (!req.url || !req.method) {
    json(res, 400, { error: { id: "bad_request", message: "Bad Request" } });
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);
  const path = url.pathname;
  const method = req.method.toUpperCase();

  if (method === "HEAD" && path === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end();
    return;
  }

  if (method === "GET" && path === "/") {
    htmlResponse(res, 200, html);
    return;
  }

  if (method === "POST" && path === "/api/auth/device-login") {
    const payload = parseJson(await readBody(req));
    if (!payload || typeof payload.deviceId !== "string" || payload.deviceId.length < 8) {
      json(res, 400, { error: { id: "bad_request", message: "deviceId 无效。" } });
      return;
    }

    const token = createToken(payload.deviceId);
    sessions.set(token, user);
    json(res, 200, { token, user, isNewUser: false });
    return;
  }

  if (method === "POST" && path === "/api/auth/request-code") {
    json(res, 200, { message: "验证码已发送。", expiresInSeconds: 300, code: "246810" });
    return;
  }

  if (method === "POST" && path === "/api/auth/verify") {
    const payload = parseJson(await readBody(req));
    if (!payload || payload.code !== "246810") {
      json(res, 400, { error: { id: "invalid_code", message: "验证码无效。" } });
      return;
    }

    const token = createToken(payload.phoneNumber || "phone-login");
    sessions.set(token, user);
    json(res, 200, { token, user });
    return;
  }

  if (method === "GET" && path === "/api/auth/me") {
    const sessionUser = requireUser(req, res);
    if (!sessionUser) {
      return;
    }
    json(res, 200, { user: sessionUser });
    return;
  }

  if (method === "POST" && path === "/api/auth/logout") {
    const token = tokenFromRequest(req);
    if (token) {
      sessions.delete(token);
    }
    json(res, 200, { success: true });
    return;
  }

  if (method === "GET" && path === "/api/dashboard") {
    json(res, 200, dashboard);
    return;
  }

  if (method === "GET" && path === "/api/reports") {
    json(res, 200, {
      generatedAt: now,
      weeklyReports: [weeklyReport],
      monthlyReports: [monthlyReport],
    });
    return;
  }

  if (method === "GET" && path.startsWith("/api/reports/")) {
    const reportId = decodeURIComponent(path.slice("/api/reports/".length));
    const report = reports.find((item) => item.id === reportId);
    if (!report) {
      notFound(res, "未找到对应报告。");
      return;
    }
    json(res, 200, report);
    return;
  }

  if (method === "GET" && path === "/api/imports") {
    json(res, 200, { tasks: importTasks });
    return;
  }

  if (method === "GET" && path.startsWith("/api/imports/")) {
    const taskId = decodeURIComponent(path.slice("/api/imports/".length));
    const task = importTasks.find((item) => item.importTaskId === taskId);
    if (!task) {
      notFound(res, "未找到对应导入任务。");
      return;
    }
    json(res, 200, { task });
    return;
  }

  if (method === "POST" && path === "/api/imports") {
    json(res, 202, { accepted: true, task: importTasks[0] });
    return;
  }

  if (method === "POST" && path === "/api/healthkit/sync") {
    json(res, 200, {
      result: {
        importTaskId: importTasks[0].importTaskId,
        taskStatus: "completed",
        totalRecords: 12,
        successRecords: 12,
        failedRecords: 0,
        syncedKinds: ["weight", "bodyFat", "exerciseMinutes", "sleepMinutes"],
        latestSampleTime: now,
      },
    });
    return;
  }

  if (method === "GET" && path === "/api/devices/status") {
    json(res, 200, deviceStatus);
    return;
  }

  if (method === "POST" && path === "/api/devices/authorize") {
    const payload = parseJson(await readBody(req));
    json(res, 501, {
      authUrl: `https://example.com/device/${payload?.provider || "unknown"}`,
      state: "mock-state",
      provider: payload?.provider || "unknown",
    });
    return;
  }

  if (method === "DELETE" && path === "/api/devices/status") {
    json(res, 200, { status: "ok", action: "disconnect", enabled: true, request: { scope: "device", confirm: true }, availableData: {}, nextStep: "设备连接已断开。" });
    return;
  }

  if (method === "GET" && path === "/api/health-plans") {
    json(res, 200, buildPlanDashboard());
    return;
  }

  if (method === "POST" && path === "/api/health-plans/generate") {
    json(res, 200, {
      batchId: "batch-1",
      suggestions: healthSuggestions,
    });
    return;
  }

  if (method === "POST" && path === "/api/health-plans/check") {
    json(res, 200, {
      checks: healthPlanChecks,
    });
    return;
  }

  if (method === "POST" && path === "/api/health-plans") {
    const payload = parseJson(await readBody(req));

    if (!payload || typeof payload.action !== "string") {
      json(res, 400, { error: { id: "bad_request", message: "缺少 action。" } });
      return;
    }

    if (payload.action === "accept") {
      const suggestion = healthSuggestions.find((item) => item.id === payload.suggestionId);
      if (!suggestion) {
        notFound(res, "未找到对应建议。");
        return;
      }

      const createdAt = new Date().toISOString();
      const planItem = {
        id: `plan-${healthPlanItems.length + 1}`,
        userId: user.id,
        suggestionId: suggestion.id,
        dimension: suggestion.dimension,
        title: suggestion.title,
        description: suggestion.description,
        targetMetricCode: payload.targetMetricCode ?? suggestion.targetMetricCode ?? null,
        targetValue: payload.targetValue ?? suggestion.targetValue ?? null,
        targetUnit: payload.targetUnit ?? suggestion.targetUnit ?? null,
        frequency: payload.frequency ?? suggestion.frequency,
        timeHint: payload.timeHint ?? suggestion.timeHint ?? null,
        status: "active",
        createdAt,
        updatedAt: createdAt,
      };
      healthPlanItems = [planItem, ...healthPlanItems];
      healthSuggestions = healthSuggestions.filter((item) => item.id !== suggestion.id);
      json(res, 200, { planItem });
      return;
    }

    if (payload.action === "check_in") {
      const check = {
        id: `check-${healthPlanChecks.length + 1}`,
        planItemId: payload.planItemId,
        checkDate: payload.date || new Date().toISOString().slice(0, 10),
        actualValue: 1,
        isCompleted: 1,
        source: "manual",
        createdAt: new Date().toISOString(),
      };
      healthPlanChecks = [check, ...healthPlanChecks];
      json(res, 200, { check });
      return;
    }

    if (payload.action === "update_status") {
      const index = healthPlanItems.findIndex((item) => item.id === payload.planItemId);
      if (index === -1) {
        notFound(res, "未找到对应计划。");
        return;
      }
      healthPlanItems[index] = {
        ...healthPlanItems[index],
        status: payload.status,
        updatedAt: new Date().toISOString(),
      };
      json(res, 200, { planItem: healthPlanItems[index] });
      return;
    }

    if (payload.action === "update_item") {
      const index = healthPlanItems.findIndex((item) => item.id === payload.planItemId);
      if (index === -1) {
        notFound(res, "未找到对应计划。");
        return;
      }
      healthPlanItems[index] = {
        ...healthPlanItems[index],
        targetValue: payload.targetValue ?? healthPlanItems[index].targetValue,
        targetUnit: payload.targetUnit ?? healthPlanItems[index].targetUnit,
        frequency: payload.frequency ?? healthPlanItems[index].frequency,
        timeHint: payload.timeHint ?? healthPlanItems[index].timeHint,
        updatedAt: new Date().toISOString(),
      };
      json(res, 200, { planItem: healthPlanItems[index] });
      return;
    }

    json(res, 400, { error: { id: "unsupported_action", message: "暂不支持该 action。" } });
    return;
  }

  if (method === "POST" && path === "/api/ai/chat") {
    const payload = parseJson(await readBody(req));
    const lastMessage = Array.isArray(payload?.messages) ? payload.messages.at(-1)?.content : "";
    json(res, 200, {
      reply: {
        id: `assistant-${Date.now()}`,
        role: "assistant",
        content: lastMessage
          ? `我已经收到你的问题：“${lastMessage}”。当前建议先优先稳定睡眠和恢复节奏，再观察一周趋势变化。`
          : "当前建议先稳定睡眠和恢复节奏。",
        createdAt: new Date().toISOString(),
      },
      provider: "mock",
      model: "healthai-chat-fallback-v1",
    });
    return;
  }

  if (method === "POST" && path === "/api/privacy/export") {
    json(res, 501, {
      status: "placeholder",
      action: "export",
      enabled: false,
      request: { scope: "all", format: "json", includeAuditLogs: false },
      requiresExplicitConfirmation: false,
      availableData: { healthRecords: 186, reports: 2, imports: 1 },
      nextStep: "当前为联调 mock 服务，隐私导出尚未接入真实流程。",
    });
    return;
  }

  if (method === "POST" && path === "/api/privacy/delete") {
    json(res, 501, {
      status: "placeholder",
      action: "delete",
      enabled: false,
      request: { scope: "all", importTaskId: null, confirm: false },
      requiresExplicitConfirmation: true,
      availableData: { healthRecords: 186, reports: 2, imports: 1 },
      nextStep: "当前为联调 mock 服务，隐私删除尚未接入真实流程。",
    });
    return;
  }

  notFound(res);
});

server.listen(port, host, () => {
  console.log(`Health LAN server running on http://${host}:${port}`);
});
