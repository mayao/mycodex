import { getAppEnv } from "../config/env";
import { classifySensitiveHeader, formatRedactionLabel, type SensitiveFieldCategory } from "../privacy/sensitive-fields";
import { normalizeHeader } from "./header-utils";
import type { ImporterSpec, MappedHeader } from "./types";

function matchesAlias(header: string, aliases: string[]): boolean {
  const normalized = normalizeHeader(header);
  return aliases.some((alias) => normalizeHeader(alias) === normalized);
}

function classifyImportField(
  header: string,
  spec: ImporterSpec,
  mappedHeaders: MappedHeader[]
): SensitiveFieldCategory {
  if (mappedHeaders.some((candidate) => candidate.header === header)) {
    return "health_metric";
  }

  if (matchesAlias(header, spec.sampleTimeAliases)) {
    return "sample_time";
  }

  if (matchesAlias(header, spec.noteAliases)) {
    return "free_text";
  }

  if (matchesAlias(header, spec.contextAliases ?? [])) {
    return "context";
  }

  return classifySensitiveHeader(header) ?? "unclassified";
}

export function buildImportAuditPayload(
  row: Record<string, string>,
  spec: ImporterSpec,
  mappedHeaders: MappedHeader[]
): Record<string, string> {
  const env = getAppEnv();

  if (env.HEALTH_IMPORT_AUDIT_MODE === "disabled") {
    return {
      _redacted: "audit logging disabled"
    };
  }

  return Object.fromEntries(
    Object.entries(row)
      .filter(([, value]) => value.trim().length > 0)
      .map(([header]) => [header, formatRedactionLabel(classifyImportField(header, spec, mappedHeaders))])
  );
}
