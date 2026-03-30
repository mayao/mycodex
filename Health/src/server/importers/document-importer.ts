import { randomUUID } from "node:crypto";
import { unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { DatabaseSync } from "node:sqlite";

import { z } from "zod";

import { getAppEnv } from "../config/env";
import { getKimiOpenAIHeaders } from "../services/llm-provider-routing";
import { importHealthData } from "./import-service";
import { importerSpecs } from "./specs";
import type { ImportExecutionResult, ImportRequest, ImporterKey } from "./types";

interface ParsedMetricCandidate {
  metricCode: string;
  value: number;
  unit?: string;
  sourceLabel?: string;
}

interface ParsedDocumentPayload {
  sampleDate: string;
  metrics: ParsedMetricCandidate[];
  parser: "llm" | "regex";
}

const llmDocumentSchema = z.object({
  sample_date: z.string().optional(),
  metrics: z.array(
    z.object({
      metric_code: z.string().min(1),
      value: z.number(),
      unit: z.string().optional(),
      source_label: z.string().optional()
    })
  )
});

function escapeCsv(value: string): string {
  if (/[",\n]/.test(value)) {
    return `"${value.replaceAll("\"", "\"\"")}"`;
  }

  return value;
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeDocumentText(text: string): string {
  return text
    .replace(/\r/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function normalizeSampleDate(dateText: string): string | undefined {
  const normalized = dateText
    .trim()
    .replaceAll("年", "-")
    .replaceAll("月", "-")
    .replaceAll("日", "")
    .replaceAll("/", "-")
    .replaceAll(".", "-");
  const match = normalized.match(/(20\d{2})-(\d{1,2})-(\d{1,2})/);

  if (!match) {
    return undefined;
  }

  const [, year, month, day] = match;
  return `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`;
}

function resolveSampleDate(text: string): string {
  const patterns = [
    /(20\d{2}[./-]\d{1,2}[./-]\d{1,2})/,
    /(20\d{2}年\d{1,2}月\d{1,2}日)/
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    const parsed = match?.[1] ? normalizeSampleDate(match[1]) : undefined;

    if (parsed) {
      return parsed;
    }
  }

  return new Date().toISOString().slice(0, 10);
}

function buildDocumentExtractionPrompt(importerKey: ImporterKey, metricCatalog: string, text: string): string {
  return `Importer: ${importerKey}

Allowed metrics:
${metricCatalog}

Return JSON:
{"sample_date":"YYYY-MM-DD","metrics":[{"metric_code":"...","value":1.23,"unit":"...","source_label":"..."}]}

Document text:
${text.slice(0, 12000)}`;
}

const DOCUMENT_SYSTEM_PROMPT =
  "You extract structured health metrics from OCR or PDF text. Return strict JSON only. Never invent unavailable metrics.";

function parseAndValidateLLMResponse(
  raw: string,
  spec: (typeof importerSpecs)[ImporterKey],
  text: string
): ParsedDocumentPayload | undefined {
  const parsed = llmDocumentSchema.safeParse(JSON.parse(raw));

  if (!parsed.success) {
    return undefined;
  }

  const allowedMetricCodes = new Set(spec.fieldMappings.map((mapping) => mapping.metricCode));
  const metrics = parsed.data.metrics.filter((metric) => allowedMetricCodes.has(metric.metric_code));

  if (metrics.length === 0) {
    return undefined;
  }

  return {
    sampleDate: normalizeSampleDate(parsed.data.sample_date ?? "") ?? resolveSampleDate(text),
    metrics: metrics.map((metric) => ({
      metricCode: metric.metric_code,
      value: metric.value,
      unit: metric.unit,
      sourceLabel: metric.source_label
    })),
    parser: "llm"
  };
}

async function tryParseWithAnthropic(
  importerKey: ImporterKey,
  text: string,
  apiKey: string,
  model: string
): Promise<ParsedDocumentPayload | undefined> {
  const spec = importerSpecs[importerKey];
  const metricCatalog = spec.fieldMappings
    .map(
      (mapping) =>
        `${mapping.metricCode} | ${mapping.metricName} | aliases=${mapping.aliases.join(",")} | unit=${mapping.canonicalUnit}`
    )
    .join("\n");

  const userPrompt = buildDocumentExtractionPrompt(importerKey, metricCatalog, text);

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01"
    },
    body: JSON.stringify({
      model,
      max_tokens: 2048,
      system: DOCUMENT_SYSTEM_PROMPT,
      messages: [{ role: "user", content: userPrompt }]
    })
  });

  if (!response.ok) {
    return undefined;
  }

  const payload = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
  };

  const raw = payload.content
    ?.filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("")
    .trim();

  if (!raw) {
    return undefined;
  }

  // Anthropic may wrap JSON in markdown code fences — strip them
  const jsonString = raw.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "").trim();

  return parseAndValidateLLMResponse(jsonString, spec, text);
}

async function tryParseWithOpenAI(
  importerKey: ImporterKey,
  text: string,
  apiKey: string,
  baseUrl: string,
  model: string
): Promise<ParsedDocumentPayload | undefined> {
  const spec = importerSpecs[importerKey];
  const metricCatalog = spec.fieldMappings
    .map(
      (mapping) =>
        `${mapping.metricCode} | ${mapping.metricName} | aliases=${mapping.aliases.join(",")} | unit=${mapping.canonicalUnit}`
    )
    .join("\n");

  const userPrompt = buildDocumentExtractionPrompt(importerKey, metricCatalog, text);

  const response = await fetch(`${baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      ...(getKimiOpenAIHeaders(apiKey) ?? {})
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: [
        { role: "system", content: DOCUMENT_SYSTEM_PROMPT },
        { role: "user", content: userPrompt }
      ]
    })
  });

  if (!response.ok) {
    return undefined;
  }

  const payload = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const raw = payload.choices?.[0]?.message?.content;

  if (!raw) {
    return undefined;
  }

  return parseAndValidateLLMResponse(raw, spec, text);
}

async function tryParseWithLLM(
  importerKey: ImporterKey,
  text: string
): Promise<ParsedDocumentPayload | undefined> {
  try {
    const env = getAppEnv();

    if (!env.HEALTH_LLM_API_KEY) {
      return undefined;
    }

    if (env.HEALTH_LLM_PROVIDER === "anthropic") {
      const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";
      return await tryParseWithAnthropic(importerKey, text, env.HEALTH_LLM_API_KEY, model);
    }

    if (env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL) {
      const model = env.HEALTH_LLM_MODEL ?? "gpt-4.1-mini";
      return await tryParseWithOpenAI(importerKey, text, env.HEALTH_LLM_API_KEY, env.HEALTH_LLM_BASE_URL, model);
    }

    return undefined;
  } catch {
    return undefined;
  }
}

function tryParseWithRegex(importerKey: ImporterKey, text: string): ParsedDocumentPayload {
  const spec = importerSpecs[importerKey];
  const normalized = normalizeDocumentText(text);
  const lines = normalized.split("\n").map((line) => line.trim()).filter(Boolean);
  const metrics = spec.fieldMappings.flatMap((mapping) => {
    const aliases = [...new Set([mapping.metricName, ...mapping.aliases])].sort(
      (left, right) => right.length - left.length
    );
    const aliasPattern = aliases.map((alias) => escapeRegex(alias)).join("|");

    for (const line of lines) {
      const regex = new RegExp(
        `(?:${aliasPattern})[^0-9-]{0,16}(-?\\d+(?:[.,]\\d+)?)\\s*([A-Za-z%/()0-9]+)?`,
        "i"
      );
      const match = line.match(regex);

      if (!match?.[1]) {
        continue;
      }

      const value = Number(match[1].replace(/,/g, ""));

      if (!Number.isFinite(value)) {
        continue;
      }

      return [
        {
          metricCode: mapping.metricCode,
          value,
          unit: match[2]?.trim(),
          sourceLabel: line.slice(0, 80)
        }
      ];
    }

    return [];
  });

  return {
    sampleDate: resolveSampleDate(normalized),
    metrics,
    parser: "regex"
  };
}

function buildSyntheticCsv(importerKey: ImporterKey, parsed: ParsedDocumentPayload): string {
  const spec = importerSpecs[importerKey];
  const byMetricCode = new Map(parsed.metrics.map((item) => [item.metricCode, item]));
  const row: Record<string, string> = {
    sample_time: parsed.sampleDate,
    notes: parsed.parser === "llm" ? "document_parser=llm" : "document_parser=regex"
  };

  for (const mapping of spec.fieldMappings) {
    const metric = byMetricCode.get(mapping.metricCode);

    if (!metric) {
      continue;
    }

    const header =
      metric.unit && metric.unit !== mapping.canonicalUnit
        ? `${mapping.metricName} (${metric.unit})`
        : mapping.metricName;
    row[header] = `${metric.value}`;
  }

  const headers = Object.keys(row);
  return `${headers.map(escapeCsv).join(",")}\n${headers.map((header) => escapeCsv(row[header] ?? "")).join(",")}\n`;
}

export async function importDocumentHealthData(
  database: DatabaseSync,
  request: ImportRequest & {
    sourceFileName: string;
    extractedText: string;
  }
): Promise<ImportExecutionResult> {
  const text = normalizeDocumentText(request.extractedText);

  if (!text) {
    throw new Error("未提取到可识别文本，无法解析图片或 PDF。");
  }

  const parsed = (await tryParseWithLLM(request.importerKey, text)) ?? tryParseWithRegex(request.importerKey, text);

  if (parsed.metrics.length === 0) {
    throw new Error("未从文档中识别到当前数据类型支持的指标。");
  }

  const syntheticFilePath = join(
    process.cwd(),
    "data",
    "uploads",
    `${Date.now()}-${randomUUID()}-${request.importerKey}-parsed.csv`
  );

  await writeFile(syntheticFilePath, buildSyntheticCsv(request.importerKey, parsed), "utf8");

  try {
    return importHealthData(database, {
      ...request,
      filePath: syntheticFilePath
    });
  } finally {
    await unlink(syntheticFilePath).catch(() => undefined);
  }
}
