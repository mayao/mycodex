import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import XLSX from "xlsx";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { formatAppDate } from "../utils/app-time";
import { importDietData } from "./diet-importer";
import { importGeneticData } from "./genetic-importer";
import { createImportTask, ensureDataSource } from "./import-task-support";
import { getFailedImportRowLogs, getImportRowLogs, importHealthData } from "./import-service";

function setupDatabase() {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);
  return database;
}

function writeTempFile(fileName: string, content: string) {
  const directory = mkdtempSync(path.join(os.tmpdir(), "health-import-"));
  const filePath = path.join(directory, fileName);
  writeFileSync(filePath, content, "utf8");

  return {
    directory,
    filePath
  };
}

async function withEnv<T>(entries: Record<string, string | undefined>, run: () => Promise<T> | T): Promise<T> {
  const previous = Object.fromEntries(
    Object.keys(entries).map((key) => [key, process.env[key]])
  );

  for (const [key, value] of Object.entries(entries)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    return await run();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

test("annual exam importer maps Chinese headers and converts mg/dL values", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "annual.csv",
    [
      "日期,身高(cm),体重(kg),BMI,血糖(mg/dL),总胆固醇(mg/dL),LDL-C(mg/dL),尿酸(umol/L),备注",
      "2026-03-01,180,80.4,24.8,100,200,130,401,annual-import-test"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "annual_exam",
      userId: "user-self",
      filePath: temp.filePath
    });

    assert.equal(result.taskStatus, "completed");
    assert.equal(result.successRecords, 7);
    assert.equal(result.warnings.length, 0);

    const glucose = database
      .prepare(
        `
        SELECT metric_code, normalized_value, unit
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'glycemic.glucose'
      `
      )
      .get(result.importTaskId) as {
      metric_code: string;
      normalized_value: number;
      unit: string;
    };

    assert.equal(glucose.metric_code, "glycemic.glucose");
    assert.equal(glucose.unit, "mmol/L");
    assert.ok(Math.abs(glucose.normalized_value - 5.55) < 0.01);
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("blood test importer flags abnormal lipid values", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "blood.csv",
    [
      "采样日期,总胆固醇(mg/dL),甘油三酯(mg/dL),高密度脂蛋白胆固醇(mg/dL),低密度脂蛋白胆固醇(mg/dL),载脂蛋白A1(g/L),载脂蛋白B(g/L),脂蛋白(a)(mg/dL),肌酐(umol/L),备注",
      "2026-03-02,250,160,35,170,1.10,1.20,80,110,blood-import-test"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "blood_test",
      userId: "user-self",
      filePath: temp.filePath
    });
    const lpaMetric = database
      .prepare(
        `
        SELECT metric_code, abnormal_flag
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'lipid.lpa'
      `
      )
      .get(result.importTaskId) as {
      metric_code: string;
      abnormal_flag: string;
    };

    const lpa = database
      .prepare(
        `
        SELECT abnormal_flag
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'lipid.lpa'
      `
      )
      .get(result.importTaskId) as { abnormal_flag: string };
    const hdl = database
      .prepare(
        `
        SELECT abnormal_flag
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'lipid.hdl_c'
      `
      )
      .get(result.importTaskId) as { abnormal_flag: string };

    assert.equal(lpaMetric.metric_code, "lipid.lpa");
    assert.equal(lpa.abnormal_flag, "high");
    assert.equal(hdl.abnormal_flag, "low");
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("body scale importer writes notes and body fat abnormal flag", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "body.csv",
    [
      "测量时间,体重(kg),体脂率(%),体水分(%),骨骼肌率(%),内脏脂肪等级(level),基础代谢(kcal),备注",
      "2026-03-06 08:11:43,78.9,22.5,56.9,44.1,6,1691,body-scale-test"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "body_scale",
      userId: "user-self",
      filePath: temp.filePath
    });

    const bodyFat = database
      .prepare(
        `
        SELECT normalized_value, abnormal_flag, notes
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'body.body_fat_pct'
      `
      )
      .get(result.importTaskId) as {
      normalized_value: number;
      abnormal_flag: string;
      notes: string;
    };

    assert.equal(bodyFat.normalized_value, 22.5);
    assert.equal(bodyFat.abnormal_flag, "high");
    assert.match(bodyFat.notes, /body-scale-test/);
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("activity importer converts duration seconds and distance meters", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "activity.csv",
    [
      "日期,运动类型,时长(s),步数,距离(m),活动能量(kcal),平均心率(bpm),备注",
      "2026-03-08,跑步,3600,12000,8500,410,145,activity-import-test"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "activity",
      userId: "user-self",
      filePath: temp.filePath
    });

    const duration = database
      .prepare(
        `
        SELECT normalized_value, unit, notes
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'activity.exercise_minutes'
      `
      )
      .get(result.importTaskId) as {
      normalized_value: number;
      unit: string;
      notes: string;
    };
    const distance = database
      .prepare(
        `
        SELECT normalized_value, unit
        FROM metric_record
        WHERE import_task_id = ? AND metric_code = 'activity.distance_km'
      `
      )
      .get(result.importTaskId) as {
      normalized_value: number;
      unit: string;
    };

    assert.equal(duration.normalized_value, 60);
    assert.equal(duration.unit, "min");
    assert.match(duration.notes, /跑步/);
    assert.equal(distance.normalized_value, 8.5);
    assert.equal(distance.unit, "km");
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("ensureDataSource scopes unified source ids by user", () => {
  const database = setupDatabase();

  database.prepare(`
    INSERT INTO users (id, display_name, sex, birth_year, height_cm, note)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run("user-other", "其他用户", "female", 1990, 165, "test user");

  const selfSourceId = ensureDataSource(database, "user-self", {
    sourceType: "apple_health",
    sourceName: "Apple 健康同步",
    ingestChannel: "healthkit",
    notes: "self"
  });
  const otherSourceId = ensureDataSource(database, "user-other", {
    sourceType: "apple_health",
    sourceName: "Apple 健康同步",
    ingestChannel: "healthkit",
    notes: "other"
  });

  assert.equal(selfSourceId, "data-source::user-self::apple_health");
  assert.equal(otherSourceId, "data-source::user-other::apple_health");
  assert.notEqual(selfSourceId, otherSourceId);

  const rows = database.prepare(`
    SELECT id, user_id, source_type
    FROM data_source
    WHERE source_type = 'apple_health'
    ORDER BY user_id
  `).all() as Array<{ id: string; user_id: string; source_type: string }>;

  assert.deepEqual(rows.map((row) => ({ ...row })), [
    {
      id: "data-source::user-other::apple_health",
      user_id: "user-other",
      source_type: "apple_health"
    },
    {
      id: "data-source::user-self::apple_health",
      user_id: "user-self",
      source_type: "apple_health"
    }
  ]);
});

test("invalid rows are tracked and import task becomes completed_with_errors", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "activity-invalid.csv",
    [
      "日期,运动类型,时长(s),步数,距离(m),活动能量(kcal),平均心率(bpm),备注",
      ",快走,1800,8000,5000,260,116,missing-date",
      "2026-03-09,跑步,not_a_number,11000,7800,390,141,invalid-duration"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "activity",
      userId: "user-self",
      filePath: temp.filePath
    });

    assert.equal(result.taskStatus, "completed_with_errors");
    assert.ok(result.failedRecords >= 6);

    const failedLogs = database
      .prepare(
        `
        SELECT COUNT(*) AS count
        FROM import_row_log
        WHERE import_task_id = ? AND row_status = 'failed'
      `
      )
      .get(result.importTaskId) as { count: number };
    const traces = getFailedImportRowLogs(database, result.importTaskId);

    assert.ok(failedLogs.count >= 6);
    assert.ok(
      traces.some(
        (trace) =>
          trace.errorMessage === "Missing or invalid sample_time" &&
          trace.rawPayload["运动类型"] === "[REDACTED:context]" &&
          trace.rawPayload["备注"] === "[REDACTED:free_text]"
      )
    );
    assert.ok(
      traces.some(
        (trace) =>
          trace.errorMessage === "Invalid numeric value" &&
          trace.rawPayload["日期"] === "[REDACTED:sample_time]" &&
          trace.rawPayload["时长(s)"] === "[REDACTED:health_metric]"
      )
    );

    const task = database
      .prepare("SELECT notes, source_file FROM import_task WHERE id = ?")
      .get(result.importTaskId) as {
      notes: string;
      source_file: string;
    };

    assert.match(task.notes, /warning_count=/);
    assert.doesNotMatch(task.notes, /missing-date|invalid-duration/);
    assert.equal(task.source_file, "activity-invalid.csv");
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("genetic importer stores structured findings from JSON into genetic_findings", async () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "genetic.json",
    JSON.stringify([
      {
        trait: "Lp(a) 背景倾向",
        gene: "LPA",
        rsid: "rs123",
        risk_level: "高风险",
        evidence_level: "A",
        summary: "提示 Lp(a) 长期偏高倾向。",
        suggestion: "建议 6-12 个月复查一次。",
        date: "2026-03-10"
      },
      {
        trait: "未知平台自定义 trait",
        gene_symbol: "GENE1",
        variant: "rs999",
        risk: "medium",
        evidence: "B",
        explanation: "这是未知 trait，也应保留。",
        advice: "继续观察。"
      }
    ]),
  );

  try {
    const dataSourceId = ensureDataSource(database, "user-self", {
      sourceType: "genetic_report",
      sourceName: "基因报告导入",
      ingestChannel: "document"
    });
    const importTaskId = createImportTask(
      database,
      { userId: "user-self" },
      {
        dataSourceId,
        taskType: "genetic_import",
        sourceType: "genetic_report",
        sourceFile: "genetic.json"
      }
    );
    const result = await importGeneticData(database, {
      userId: "user-self",
      filePath: temp.filePath,
      sourceFileName: "genetic.json",
      importTaskId,
      dataSourceId
    });

    assert.equal(result.taskStatus, "completed");

    const rows = database.prepare(`
      SELECT trait_code, gene_symbol, summary
      FROM genetic_findings
      WHERE source_id = ?
      ORDER BY trait_code
    `).all(dataSourceId) as Array<{
      trait_code: string;
      gene_symbol: string;
      summary: string;
    }>;

    assert.equal(rows.length, 2);
    assert.equal(rows[0]?.trait_code, "custom.未知平台自定义.trait");
    assert.equal(rows[1]?.trait_code, "lipid.lpa_background");
    assert.ok(rows.some((row) => row.summary.includes("未知 trait")));
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("genetic importer parses OCR text with line-pair and broader risk expressions", async () => {
  const database = setupDatabase();
  const temp = writeTempFile("genetic-report.jpg", "fake-image");

  try {
    const dataSourceId = ensureDataSource(database, "user-self", {
      sourceType: "genetic_report",
      sourceName: "基因报告导入",
      ingestChannel: "document"
    });
    const importTaskId = createImportTask(
      database,
      { userId: "user-self" },
      {
        dataSourceId,
        taskType: "genetic_import",
        sourceType: "genetic_report",
        sourceFile: "genetic-report.jpg"
      }
    );
    const result = await importGeneticData(database, {
      userId: "user-self",
      filePath: temp.filePath,
      sourceFileName: "genetic-report.jpg",
      importTaskId,
      dataSourceId,
      extractedText: [
        "Lp(a) 背景倾向",
        "较高",
        "咖啡因代谢",
        "正常",
        "餐后血糖敏感性 高风险"
      ].join("\n")
    });

    assert.equal(result.taskStatus, "completed");

    const rows = database.prepare(`
      SELECT trait_code, risk_level
      FROM genetic_findings
      WHERE source_id = ?
      ORDER BY trait_code
    `).all(dataSourceId) as Array<{ trait_code: string; risk_level: string }>;

    assert.ok(rows.some((row) => row.trait_code === "lipid.lpa_background" && row.risk_level === "high"));
    assert.ok(rows.some((row) => row.trait_code === "sleep.caffeine_sensitivity" && row.risk_level === "low"));
    assert.ok(rows.some((row) => row.trait_code === "glycemic.postprandial_response" && row.risk_level === "high"));
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("genetic importer falls back to vision parsing when OCR text is empty", async () => {
  const database = setupDatabase();
  const temp = writeTempFile("genetic-photo.jpg", "fake-image");
  const dataSourceId = ensureDataSource(database, "user-self", {
    sourceType: "genetic_report",
    sourceName: "基因报告导入",
    ingestChannel: "document"
  });
  const importTaskId = createImportTask(
    database,
    { userId: "user-self" },
    {
      dataSourceId,
      taskType: "genetic_import",
      sourceType: "genetic_report",
      sourceFile: "genetic-photo.jpg"
    }
  );
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [
          {
            message: {
              content: JSON.stringify({
                findings: [
                  {
                    trait_label: "Lp(a) 背景倾向",
                    trait_code: "lipid.lpa_background",
                    risk_level: "high",
                    evidence_level: "A",
                    summary: "提示 Lp(a) 背景偏高倾向。",
                    suggestion: "建议结合血脂长期复查。",
                    gene_symbol: "LPA",
                    variant_id: "rs123",
                    recorded_at: "2026-03-20"
                  }
                ]
              })
            }
          }
        ],
        model: "vision-mock"
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" }
      }
    ) as Response;

  try {
    const result = await withEnv(
      {
        HEALTH_LLM_PROVIDER: "openai-compatible",
        HEALTH_LLM_API_KEY: "test-key",
        HEALTH_LLM_BASE_URL: "https://example.com/v1"
      },
      () =>
        importGeneticData(database, {
          userId: "user-self",
          filePath: temp.filePath,
          sourceFileName: "genetic-photo.jpg",
          importTaskId,
          dataSourceId,
          extractedText: ""
        })
    );

    assert.equal(result.taskStatus, "completed");

    const row = database.prepare(`
      SELECT trait_code, gene_symbol
      FROM genetic_findings
      WHERE source_id = ?
      LIMIT 1
    `).get(dataSourceId) as { trait_code: string; gene_symbol: string };

    assert.equal(row.trait_code, "lipid.lpa_background");
    assert.equal(row.gene_symbol, "LPA");
  } finally {
    globalThis.fetch = originalFetch;
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("diet importer fails with a clear error when no vision model is configured", async () => {
  const database = setupDatabase();
  const temp = writeTempFile("diet.jpg", "fake-image-content");
  const dataSourceId = ensureDataSource(database, "user-self", {
    sourceType: "diet_image",
    sourceName: "饮食健康导入",
    ingestChannel: "document"
  });

  await assert.rejects(
    async () =>
      withEnv(
        {
          HEALTH_LLM_PROVIDER: undefined,
          HEALTH_LLM_API_KEY: undefined,
          HEALTH_LLM_BASE_URL: undefined
        },
        () =>
          importDietData(database, {
            userId: "user-self",
            filePath: temp.filePath,
            sourceFileName: "diet.jpg",
            importTaskId: "import-task::diet-no-model",
            dataSourceId
          })
      ),
    /图像分析模型|支持视觉|饮食图片无法识别/
  );

  rmSync(temp.directory, { recursive: true, force: true });
});

test("diet importer aggregates same-day calories and upload count", async () => {
  const database = setupDatabase();
  const temp = writeTempFile("diet.jpg", "fake-image-content");
  const expectedAppDate = formatAppDate(new Date());
  const dataSourceId = ensureDataSource(database, "user-self", {
    sourceType: "diet_image",
    sourceName: "饮食健康导入",
    ingestChannel: "document"
  });
  const importTaskId1 = createImportTask(
    database,
    { userId: "user-self" },
    {
      dataSourceId,
      taskType: "diet_import",
      sourceType: "diet_image",
      sourceFile: "diet.jpg"
    }
  );
  const importTaskId2 = createImportTask(
    database,
    { userId: "user-self" },
    {
      dataSourceId,
      taskType: "diet_import",
      sourceType: "diet_image",
      sourceFile: "diet.jpg"
    }
  );
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [
          {
            message: {
              content: JSON.stringify({
                foods: ["鸡胸肉", "米饭", "西兰花"],
                estimated_calories_kcal: 620
              })
            }
          }
        ],
        model: "vision-mock"
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" }
      }
    ) as Response;

  try {
    await withEnv(
      {
        HEALTH_LLM_PROVIDER: "openai-compatible",
        HEALTH_LLM_API_KEY: "test-key",
        HEALTH_LLM_BASE_URL: "https://example.com/v1"
      },
      async () => {
        await importDietData(database, {
          userId: "user-self",
          filePath: temp.filePath,
          sourceFileName: "diet.jpg",
          importTaskId: importTaskId1,
          dataSourceId
        });
        await importDietData(database, {
          userId: "user-self",
          filePath: temp.filePath,
          sourceFileName: "diet.jpg",
          importTaskId: importTaskId2,
          dataSourceId
        });
      }
    );

    const rows = database.prepare(`
      SELECT metric_code, normalized_value
      FROM metric_record
      WHERE user_id = ? AND sample_time LIKE ?
      ORDER BY metric_code
    `).all("user-self", `${expectedAppDate}%`) as Array<{ metric_code: string; normalized_value: number }>;

    assert.deepEqual(rows.map((row) => [row.metric_code, row.normalized_value]), [
      ["diet.calories_intake_kcal", 1240],
      ["diet.meal_upload_count", 2]
    ]);
  } finally {
    globalThis.fetch = originalFetch;
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("diet importer estimates calories when model omits numeric calories field", async () => {
  const database = setupDatabase();
  const temp = writeTempFile("diet-estimate.jpg", "fake-image-content");
  const expectedAppDate = formatAppDate(new Date());
  const dataSourceId = ensureDataSource(database, "user-self", {
    sourceType: "diet_image",
    sourceName: "饮食健康导入",
    ingestChannel: "document"
  });
  const importTaskId = createImportTask(
    database,
    { userId: "user-self" },
    {
      dataSourceId,
      taskType: "diet_import",
      sourceType: "diet_image",
      sourceFile: "diet-estimate.jpg"
    }
  );
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [
          {
            message: {
              content: JSON.stringify({
                foods: ["鸡胸肉", "米饭", "西兰花"]
              })
            }
          }
        ],
        model: "vision-mock"
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" }
      }
    ) as Response;

  try {
    const result = await withEnv(
      {
        HEALTH_LLM_PROVIDER: "openai-compatible",
        HEALTH_LLM_API_KEY: "test-key",
        HEALTH_LLM_BASE_URL: "https://example.com/v1"
      },
      () =>
        importDietData(database, {
          userId: "user-self",
          filePath: temp.filePath,
          sourceFileName: "diet-estimate.jpg",
          importTaskId,
          dataSourceId
        })
    );

    assert.equal(result.taskStatus, "completed");

    const rows = database.prepare(`
      SELECT metric_code, normalized_value
      FROM metric_record
      WHERE import_task_id = ?
      ORDER BY metric_code
    `).all(importTaskId) as Array<{ metric_code: string; normalized_value: number }>;

    assert.deepEqual(rows.map((row) => [row.metric_code, row.normalized_value]), [
      ["diet.calories_intake_kcal", 550],
      ["diet.meal_upload_count", 1]
    ]);

    const aggregateDate = database.prepare(`
      SELECT sample_time
      FROM metric_record
      WHERE import_task_id = ? AND metric_code = 'diet.calories_intake_kcal'
    `).get(importTaskId) as { sample_time: string };

    assert.ok(aggregateDate.sample_time.startsWith(expectedAppDate));
  } finally {
    globalThis.fetch = originalFetch;
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("diet importer falls back to gemini when the primary vision provider fails", async () => {
  const database = setupDatabase();
  const temp = writeTempFile("diet-fallback.jpg", "fake-image-content");
  const dataSourceId = ensureDataSource(database, "user-self", {
    sourceType: "diet_image",
    sourceName: "饮食健康导入",
    ingestChannel: "document"
  });
  const importTaskId = createImportTask(
    database,
    { userId: "user-self" },
    {
      dataSourceId,
      taskType: "diet_import",
      sourceType: "diet_image",
      sourceFile: "diet-fallback.jpg"
    }
  );
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async (input) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

    if (url.includes("api.anthropic.com")) {
      return new Response("upstream error", { status: 500 }) as Response;
    }

    if (url.includes("generativelanguage.googleapis.com")) {
      return new Response(
        JSON.stringify({
          choices: [
            {
              message: {
                content: JSON.stringify({
                  foods: ["鸡蛋", "酸奶", "香蕉"],
                  estimated_calories_kcal: 430
                })
              }
            }
          ],
          model: "gemini-vision-mock"
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" }
        }
      ) as Response;
    }

    throw new Error(`Unexpected fetch: ${url}`);
  };

  try {
    const result = await withEnv(
      {
        HEALTH_LLM_PROVIDER: "anthropic",
        HEALTH_LLM_API_KEY: "anthropic-key",
        HEALTH_LLM_MODEL: "claude-opus-test",
        HEALTH_LLM_FALLBACK_GEMINI_KEY: "gemini-key",
        HEALTH_LLM_FALLBACK_GEMINI_MODEL: "gemini-2.5-flash"
      },
      () =>
        importDietData(database, {
          userId: "user-self",
          filePath: temp.filePath,
          sourceFileName: "diet-fallback.jpg",
          importTaskId,
          dataSourceId
        })
    );

    assert.equal(result.taskStatus, "completed");

    const row = database.prepare(`
      SELECT normalized_value
      FROM metric_record
      WHERE import_task_id = ? AND metric_code = 'diet.calories_intake_kcal'
    `).get(importTaskId) as { normalized_value: number };

    assert.equal(row.normalized_value, 430);
  } finally {
    globalThis.fetch = originalFetch;
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("audit mode disabled stores a single placeholder instead of field labels", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "activity-invalid.csv",
    [
      "日期,运动类型,时长(s),步数,距离(m),活动能量(kcal),平均心率(bpm),备注",
      ",快走,1800,8000,5000,260,116,missing-date"
    ].join("\n")
  );

  try {
    withEnv(
      {
        HEALTH_IMPORT_AUDIT_MODE: "disabled"
      },
      () => {
        const result = importHealthData(database, {
          importerKey: "activity",
          userId: "user-self",
          filePath: temp.filePath
        });
        const traces = getFailedImportRowLogs(database, result.importTaskId);

        assert.deepEqual(traces[0]?.rawPayload, {
          _redacted: "audit logging disabled"
        });
      }
    );
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("xlsx files are supported by the same importer flow", () => {
  const database = setupDatabase();
  const directory = mkdtempSync(path.join(os.tmpdir(), "health-import-xlsx-"));
  const filePath = path.join(directory, "body-scale.xlsx");
  const worksheet = XLSX.utils.json_to_sheet([
    {
      "测量时间": "2026-03-06 08:11:43",
      "体重(kg)": 78.9,
      "体脂率(%)": 22.5,
      "体水分(%)": 56.9,
      "骨骼肌率(%)": 44.1,
      "内脏脂肪等级(level)": 6,
      "基础代谢(kcal)": 1691,
      "备注": "xlsx-import-test"
    }
  ]);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "Sheet1");
  XLSX.writeFile(workbook, filePath);

  try {
    const result = importHealthData(database, {
      importerKey: "body_scale",
      userId: "user-self",
      filePath
    });

    assert.equal(result.taskStatus, "completed");
    assert.equal(result.successRecords, 6);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("unmapped headers are surfaced as warnings without blocking mapped fields", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "body-warning.csv",
    [
      "测量时间,体重(kg),体脂率(%),未知字段,备注",
      "2026-03-06 08:11:43,78.9,22.5,foo,warning-test"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "body_scale",
      userId: "user-self",
      filePath: temp.filePath
    });

    assert.equal(result.taskStatus, "completed");
    assert.ok(result.warnings.some((warning) => warning.header === "未知字段"));
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("rows without mapped metric values are logged as skipped", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "activity-skip.csv",
    [
      "日期,运动类型,时长(s),备注",
      "2026-03-08,散步,,only-context"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "activity",
      userId: "user-self",
      filePath: temp.filePath
    });
    const logs = getImportRowLogs(database, result.importTaskId);

    assert.equal(result.taskStatus, "failed");
    assert.ok(logs.some((log) => log.rowStatus === "skipped" && log.rowNumber === 2));
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});

test("files with no supported headers fail with a descriptive warning", () => {
  const database = setupDatabase();
  const temp = writeTempFile(
    "unsupported.csv",
    [
      "日期,指标A,指标B",
      "2026-03-08,1,2"
    ].join("\n")
  );

  try {
    const result = importHealthData(database, {
      importerKey: "activity",
      userId: "user-self",
      filePath: temp.filePath
    });

    assert.equal(result.taskStatus, "failed");
    assert.ok(result.warnings.some((warning) => warning.code === "no_mapped_headers"));
  } finally {
    rmSync(temp.directory, { recursive: true, force: true });
  }
});
