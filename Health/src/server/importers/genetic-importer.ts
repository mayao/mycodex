import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { extname } from "node:path";
import type { DatabaseSync } from "node:sqlite";

import { callVisionLLMWithFallbacks, isVisionImageFile } from "../services/vision-llm-service";
import { formatAppDateTimeIso } from "../utils/app-time";
import {
  appendTaskNotes,
  finalizeImportTask,
  insertImportRowLog
} from "./import-task-support";
import { readTabularFile } from "./tabular-reader";
import type { ImportExecutionResult } from "./types";

type RiskLevel = "low" | "medium" | "high";
type EvidenceLevel = "A" | "B" | "C";

interface GeneticImportRequest {
  userId: string;
  filePath: string;
  sourceFileName: string;
  importTaskId: string;
  dataSourceId: string;
  taskNotes?: string;
  extractedText?: string;
}

interface GeneticCandidate {
  traitLabel?: string;
  traitCode?: string;
  riskLevel?: string;
  evidenceLevel?: string;
  summary?: string;
  suggestion?: string;
  geneSymbol?: string;
  variantId?: string;
  recordedAt?: string;
  rawPayload: Record<string, unknown>;
}

interface NormalizedGeneticFinding {
  traitLabel: string;
  traitCode: string;
  riskLevel: RiskLevel;
  evidenceLevel: EvidenceLevel;
  summary: string;
  suggestion: string;
  geneSymbol: string;
  variantId: string;
  recordedAt: string;
  rawPayload: Record<string, unknown>;
}

const knownTraits: Array<{
  traitCode: string;
  label: string;
  aliases: string[];
}> = [
  {
    traitCode: "lipid.lpa_background",
    label: "Lp(a) 背景倾向",
    aliases: ["lp(a)", "lpa", "脂蛋白a", "脂蛋白(a)", "lp a"]
  },
  {
    traitCode: "lipid.ldl_clearance_response",
    label: "LDL-C 清除敏感性",
    aliases: ["ldl", "ldl-c", "低密度脂蛋白", "胆固醇清除"]
  },
  {
    traitCode: "body.weight_regain_tendency",
    label: "体脂反弹敏感性",
    aliases: ["体重反弹", "减重反弹", "weight regain", "body fat rebound", "肥胖易感"]
  },
  {
    traitCode: "glycemic.postprandial_response",
    label: "餐后血糖敏感性",
    aliases: ["餐后血糖", "postprandial glucose", "glucose response", "血糖敏感"]
  },
  {
    traitCode: "sleep.caffeine_sensitivity",
    label: "咖啡因敏感性",
    aliases: ["咖啡因", "caffeine", "睡眠敏感", "代谢咖啡因"]
  },
  {
    traitCode: "activity.endurance_response",
    label: "耐力训练响应",
    aliases: ["耐力", "endurance", "有氧训练响应", "运动恢复"]
  }
];

function normalizeKey(value: string): string {
  return value.toLowerCase().replace(/[\s_\-()（）[\]【】]+/g, "");
}

function normalizeRiskLevel(value: string | undefined): RiskLevel {
  const normalized = (value ?? "").toLowerCase();

  if (/high|高风险|较高|偏高|高于平均|风险高|风险增加|易感|需关注|不利|异常|阳性/.test(normalized)) {
    return "high";
  }

  if (/medium|mid|中风险|中等|一般|普通/.test(normalized)) {
    return "medium";
  }

  return "low";
}

function normalizeEvidenceLevel(value: string | undefined): EvidenceLevel {
  const upper = (value ?? "").trim().toUpperCase();

  if (upper === "A" || /high|strong|高/.test(upper.toLowerCase())) {
    return "A";
  }

  if (upper === "C" || /low|弱|初步/.test(upper.toLowerCase())) {
    return "C";
  }

  return "B";
}

function normalizeDate(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const trimmed = value
    .trim()
    .replaceAll("年", "-")
    .replaceAll("月", "-")
    .replaceAll("日", "")
    .replaceAll("/", "-")
    .replaceAll(".", "-");
  const match = trimmed.match(/(20\d{2})-(\d{1,2})-(\d{1,2})/);

  if (!match) return undefined;

  const [, year, month, day] = match;
  return `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}T08:00:00+08:00`;
}

function slugify(value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ".")
    .replace(/\.+/g, ".")
    .replace(/^\./, "")
    .replace(/\.$/, "");
  return slug || randomUUID().slice(0, 8);
}

function resolveKnownTrait(traitLabel: string): { traitCode: string; label: string } | undefined {
  const normalizedLabel = traitLabel.toLowerCase();
  const matched = knownTraits.find((item) =>
    item.aliases.some((alias) => normalizedLabel.includes(alias.toLowerCase()))
  );

  if (!matched) return undefined;

  return {
    traitCode: matched.traitCode,
    label: matched.label
  };
}

function extractFromRecord(record: Record<string, unknown>, aliases: string[]): string | undefined {
  const normalizedAliasSet = new Set(aliases.map((alias) => normalizeKey(alias)));

  for (const [key, value] of Object.entries(record)) {
    if (!normalizedAliasSet.has(normalizeKey(key))) continue;
    const text = String(value ?? "").trim();
    if (text) return text;
  }

  return undefined;
}

function rowToCandidate(row: Record<string, unknown>): GeneticCandidate {
  return {
    traitLabel: extractFromRecord(row, ["trait", "trait_label", "trait_name", "项目", "维度", "特征", "表型"]),
    traitCode: extractFromRecord(row, ["trait_code", "traitcode", "编码"]),
    riskLevel: extractFromRecord(row, ["risk", "risk_level", "风险", "风险等级"]),
    evidenceLevel: extractFromRecord(row, ["evidence", "evidence_level", "证据", "证据等级"]),
    summary: extractFromRecord(row, ["summary", "explanation", "解读", "说明", "摘要"]),
    suggestion: extractFromRecord(row, ["suggestion", "advice", "action", "建议"]),
    geneSymbol: extractFromRecord(row, ["gene", "gene_symbol", "基因", "gene symbol"]),
    variantId: extractFromRecord(row, ["variant", "rsid", "位点", "位点编号"]),
    recordedAt: extractFromRecord(row, ["recorded_at", "date", "检测日期", "日期", "sample_time"]),
    rawPayload: row
  };
}

function parseJsonCandidates(filePath: string): GeneticCandidate[] {
  const raw = readFileSync(filePath, "utf8");
  const parsed = JSON.parse(raw) as unknown;

  const rows = Array.isArray(parsed)
    ? parsed
    : typeof parsed === "object" && parsed !== null && Array.isArray((parsed as { findings?: unknown[] }).findings)
      ? (parsed as { findings: unknown[] }).findings
      : [parsed];

  return rows
    .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
    .map((item) => rowToCandidate(item));
}

function parseTabularCandidates(filePath: string): GeneticCandidate[] {
  const table = readTabularFile(filePath);
  return table.rows.map((row) => rowToCandidate(row));
}

function riskFromSnippet(text: string): string | undefined {
  if (/高风险|风险高|high risk|较高|偏高|高于平均|风险增加|易感|需关注|不利/i.test(text)) return "high";
  if (/中风险|风险中|medium risk|medium|中等|一般/i.test(text)) return "medium";
  if (/低风险|风险低|low risk|low|较低|偏低|低于平均|正常|未见明显风险/i.test(text)) return "low";
  return undefined;
}

function cleanTraitLabel(value: string): string {
  return value
    .replace(/[\s:：-]+(高风险|中风险|低风险|较高|较低|偏高|偏低|高于平均|低于平均|风险增加|风险降低|正常|一般)$/i, "")
    .replace(/^(trait|项目|维度|特征|表型)[\s:：-]*/i, "")
    .trim();
}

function looksLikeTraitLabel(value: string): boolean {
  const trimmed = cleanTraitLabel(value);

  if (trimmed.length < 2 || trimmed.length > 36) {
    return false;
  }

  if (/^(rs\d+|gene|risk|high|medium|low)$/i.test(trimmed)) {
    return false;
  }

  return /[\u4e00-\u9fa5A-Za-z]/.test(trimmed);
}

function parseLinewiseCandidates(text: string): GeneticCandidate[] {
  const lines = text
    .replace(/\r/g, "\n")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const candidates: GeneticCandidate[] = [];
  const inlineRegex =
    /^([A-Za-z0-9+\-()（）/\u4e00-\u9fa5]{2,40}?)[\s:：\-|]{1,8}(高风险|中风险|低风险|较高|较低|偏高|偏低|高于平均|低于平均|风险增加|风险降低|正常|一般|high risk|medium risk|low risk)$/i;

  for (const line of lines) {
    const inlineMatch = line.match(inlineRegex);
    if (inlineMatch?.[1] && inlineMatch[2]) {
      candidates.push({
        traitLabel: cleanTraitLabel(inlineMatch[1]),
        riskLevel: inlineMatch[2],
        summary: line.slice(0, 200),
        rawPayload: {
          parser: "ocr_line",
          line
        }
      });
    }
  }

  for (let index = 0; index < lines.length - 1; index += 1) {
    const current = lines[index] ?? "";
    const next = lines[index + 1] ?? "";
    const nextRisk = riskFromSnippet(next);

    if (looksLikeTraitLabel(current) && nextRisk) {
      candidates.push({
        traitLabel: cleanTraitLabel(current),
        riskLevel: nextRisk,
        summary: `${current} ${next}`.trim().slice(0, 200),
        rawPayload: {
          parser: "ocr_line_pair",
          lines: [current, next]
        }
      });
    }
  }

  return candidates;
}

function parseTextCandidates(text: string): GeneticCandidate[] {
  const normalized = text.replace(/\r/g, "\n");
  const candidates: GeneticCandidate[] = [];

  for (const trait of knownTraits) {
    const matchedAlias = trait.aliases.find((alias) =>
      normalized.toLowerCase().includes(alias.toLowerCase())
    );
    if (!matchedAlias) continue;
    const index = normalized.toLowerCase().indexOf(matchedAlias.toLowerCase());
    const snippet = normalized.slice(Math.max(0, index - 80), index + 160);
    candidates.push({
      traitLabel: trait.label,
      traitCode: trait.traitCode,
      riskLevel: riskFromSnippet(snippet),
      summary: snippet.trim().slice(0, 200),
      rawPayload: {
        parser: "ocr",
        matchedAlias,
        snippet
      }
    });
  }

  const genericRegex =
    /([A-Za-z0-9+\-()（）/\u4e00-\u9fa5]{2,36}?)[\s:：\-|]{0,8}(高风险|中风险|低风险|风险高|风险中|风险低|较高|较低|偏高|偏低|高于平均|低于平均|风险增加|风险降低|正常|一般|high risk|medium risk|low risk)/gi;
  const genericMatches = normalized.matchAll(genericRegex);

  for (const match of genericMatches) {
    const traitLabel = cleanTraitLabel(match[1] ?? "");
    const risk = match[2]?.trim();

    if (!traitLabel || !risk) continue;
    if (candidates.some((item) => item.traitLabel === traitLabel)) continue;

    candidates.push({
      traitLabel,
      riskLevel: risk,
      rawPayload: {
        parser: "ocr",
        match: match[0]
      }
    });
  }

  for (const candidate of parseLinewiseCandidates(normalized)) {
    if (!candidate.traitLabel) continue;
    if (candidates.some((item) => item.traitLabel === candidate.traitLabel)) continue;
    candidates.push(candidate);
  }

  return candidates;
}

function parseVisionCandidates(raw: string): GeneticCandidate[] {
  const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();

  try {
    const jsonMatch = cleaned.match(/\{[\s\S]*\}|\[[\s\S]*\]/);
    const payload = JSON.parse(jsonMatch?.[0] ?? cleaned) as
      | { findings?: unknown[] }
      | unknown[];
    const rows = Array.isArray(payload)
      ? payload
      : Array.isArray(payload.findings)
        ? payload.findings
        : [];

    return rows
      .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
      .map((item) => rowToCandidate(item));
  } catch {
    return parseTextCandidates(cleaned);
  }
}

function mergeCandidates(primary: GeneticCandidate[], secondary: GeneticCandidate[]): GeneticCandidate[] {
  const seen = new Set<string>();
  const merged: GeneticCandidate[] = [];

  for (const candidate of [...primary, ...secondary]) {
    const key = normalizeKey(candidate.traitCode ?? candidate.traitLabel ?? "");
    if (!key || seen.has(key)) {
      continue;
    }
    seen.add(key);
    merged.push(candidate);
  }

  return merged;
}

function buildGeneticVisionPrompt(ocrText?: string): string {
  const ocrHint =
    ocrText && ocrText.trim().length > 0
      ? [
          "以下是同一文件的 OCR 文本片段，可作为辅助线索，但请以图片内容为准：",
          ocrText.trim().slice(0, 1200)
        ].join("\n")
      : "当前没有可靠 OCR 文本，请直接从图片中识别。";

  return [
    "请把这张基因检测/遗传风险报告图片解析为结构化 finding。",
    "只返回 JSON，不要包含 markdown 代码块。",
    '返回格式：{"findings":[{"trait_label":"Lp(a) 背景倾向","trait_code":"lipid.lpa_background","risk_level":"high","evidence_level":"A","summary":"...","suggestion":"...","gene_symbol":"LPA","variant_id":"rs123","recorded_at":"2026-03-20"}]}',
    "要求：",
    "1. findings 最多返回 12 条最有信息量的结果。",
    "2. risk_level 只能是 low / medium / high。",
    "3. evidence_level 只能是 A / B / C；无法判断时用 B。",
    "4. trait_code 尽量规范；无法确定时留空即可。",
    "5. 如果无法识别任何基因 finding，请返回 {\"findings\":[]}。",
    ocrHint
  ].join("\n");
}

async function parseVisionCandidatesFromImage(request: GeneticImportRequest): Promise<GeneticCandidate[]> {
  const result = await callVisionLLMWithFallbacks({
    filePath: request.filePath,
    prompt: buildGeneticVisionPrompt(request.extractedText),
    timeoutMs: 75_000
  });

  return parseVisionCandidates(result.text).map((candidate) => ({
    ...candidate,
    rawPayload: {
      ...candidate.rawPayload,
      parser: "vision",
      provider: result.provider,
      model: result.model
    }
  }));
}

function normalizeCandidate(candidate: GeneticCandidate): NormalizedGeneticFinding | null {
  const explicitTraitLabel = candidate.traitLabel?.trim();
  const explicitTraitCode = candidate.traitCode?.trim();

  if (!explicitTraitLabel && !explicitTraitCode) {
    return null;
  }

  const traitLookup = resolveKnownTrait(explicitTraitLabel ?? explicitTraitCode ?? "");
  const traitCode =
    explicitTraitCode && explicitTraitCode.length > 0
      ? explicitTraitCode
      : traitLookup?.traitCode ?? `custom.${slugify(explicitTraitLabel ?? explicitTraitCode ?? "trait")}`;
  const traitLabel = traitLookup?.label ?? explicitTraitLabel ?? explicitTraitCode ?? "未知 trait";
  const riskLevel = normalizeRiskLevel(candidate.riskLevel);
  const evidenceLevel = normalizeEvidenceLevel(candidate.evidenceLevel);
  const recordedAt = normalizeDate(candidate.recordedAt) ?? formatAppDateTimeIso(new Date());
  const geneSymbol =
    candidate.geneSymbol?.trim() ||
    (explicitTraitLabel?.match(/\b[A-Z0-9]{3,10}\b/)?.[0] ?? "N/A");

  return {
    traitLabel,
    traitCode,
    riskLevel,
    evidenceLevel,
    summary:
      candidate.summary?.trim() ||
      `${traitLabel} 已识别为${riskLevel === "high" ? "高" : riskLevel === "medium" ? "中" : "低"}风险倾向，建议与近期体检和行为数据联动观察。`,
    suggestion:
      candidate.suggestion?.trim() ||
      "建议结合近期血脂、体重、运动和睡眠记录，持续 3-6 个月跟踪同一维度变化。",
    geneSymbol,
    variantId: candidate.variantId?.trim() || `unknown-${randomUUID().slice(0, 8)}`,
    recordedAt,
    rawPayload: {
      ...candidate.rawPayload,
      normalized_trait_label: traitLabel
    }
  };
}

async function parseCandidates(request: GeneticImportRequest): Promise<{ parser: string; candidates: GeneticCandidate[] }> {
  const extension = extname(request.sourceFileName).toLowerCase();

  if (extension === ".json") {
    return {
      parser: "json",
      candidates: parseJsonCandidates(request.filePath)
    };
  }

  if ([".csv", ".xlsx", ".xls"].includes(extension)) {
    return {
      parser: "tabular",
      candidates: parseTabularCandidates(request.filePath)
    };
  }

  const text = request.extractedText?.trim();
  const ocrCandidates = text ? parseTextCandidates(text) : [];
  const shouldUseVisionFallback =
    isVisionImageFile(request.sourceFileName) &&
    (!text || ocrCandidates.length < 2);

  if (shouldUseVisionFallback) {
    const visionCandidates = await parseVisionCandidatesFromImage(request);
    const merged = mergeCandidates(ocrCandidates, visionCandidates);

    if (merged.length > 0) {
      return {
        parser: ocrCandidates.length > 0 ? "ocr+vision" : "vision",
        candidates: merged
      };
    }
  }

  if (!text) {
    throw new Error("未提取到可识别文本，且图片视觉解析未得到结果。请上传更清晰的基因报告图片，或使用 CSV/JSON/XLSX。");
  }

  return {
    parser: "ocr",
    candidates: ocrCandidates
  };
}

export async function importGeneticData(
  database: DatabaseSync,
  request: GeneticImportRequest
): Promise<ImportExecutionResult> {
  const { parser, candidates } = await parseCandidates(request);
  const normalized = candidates
    .map((candidate) => normalizeCandidate(candidate))
    .filter((item): item is NormalizedGeneticFinding => Boolean(item));

  if (normalized.length === 0) {
    throw new Error("未识别到可导入的基因 finding。请检查文件是否包含 trait/risk/evidence 等字段。");
  }

  let successRecords = 0;
  let failedRecords = 0;
  let totalRecords = 0;

  database.exec("BEGIN");

  try {
    for (let index = 0; index < normalized.length; index += 1) {
      const rowNumber = index + 1;
      const finding = normalized[index];
      totalRecords += 1;

      try {
        database
          .prepare(
            `
            INSERT INTO genetic_findings (
              id,
              user_id,
              source_id,
              gene_symbol,
              variant_id,
              trait_code,
              risk_level,
              evidence_level,
              summary,
              suggestion,
              recorded_at,
              raw_payload_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `
          )
          .run(
            `genetic-finding::${randomUUID()}`,
            request.userId,
            request.dataSourceId,
            finding.geneSymbol,
            finding.variantId,
            finding.traitCode,
            finding.riskLevel,
            finding.evidenceLevel,
            finding.summary,
            finding.suggestion,
            finding.recordedAt,
            JSON.stringify({
              parser,
              sourceFile: request.sourceFileName,
              traitLabel: finding.traitLabel,
              ...finding.rawPayload
            })
          );

        insertImportRowLog(
          database,
          request.importTaskId,
          {
            rowNumber,
            status: "imported",
            metricCode: finding.traitCode,
            sourceField: "trait_code"
          },
          {
            trait: finding.traitLabel,
            risk_level: finding.riskLevel,
            evidence_level: finding.evidenceLevel
          }
        );
        successRecords += 1;
      } catch (error) {
        failedRecords += 1;
        insertImportRowLog(
          database,
          request.importTaskId,
          {
            rowNumber,
            status: "failed",
            metricCode: finding.traitCode,
            sourceField: "trait_code",
            errorMessage: error instanceof Error ? error.message : "failed to insert finding"
          },
          {
            trait: finding.traitLabel
          }
        );
      }
    }

    database.exec("COMMIT");
  } catch {
    database.exec("ROLLBACK");
    throw new Error("基因导入事务执行失败。");
  }

  const taskStatus =
    successRecords === 0 && failedRecords > 0
      ? "failed"
      : failedRecords > 0
        ? "completed_with_errors"
        : "completed";

  finalizeImportTask(
    database,
    request.importTaskId,
    taskStatus,
    totalRecords,
    successRecords,
    failedRecords,
    appendTaskNotes(request.taskNotes, `genetic_parser=${parser} | finding_count=${successRecords}`)
  );

  return {
    importTaskId: request.importTaskId,
    importerKey: "genetic",
    filePath: request.filePath,
    taskStatus,
    totalRecords,
    successRecords,
    failedRecords,
    logSummary: [],
    warnings: []
  };
}
