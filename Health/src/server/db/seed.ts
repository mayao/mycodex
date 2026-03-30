import type { DatabaseSync } from "node:sqlite";

import {
  dataSources,
  geneticFindings,
  measurementSets,
  metricCatalog,
  seedVersion,
  users
} from "../../data/mock/seed-data";

export const SEED_VERSION = seedVersion;

export function seedDatabase(database: DatabaseSync): void {
  const insertUser = database.prepare(`
    INSERT INTO users (id, display_name, sex, birth_year, height_cm, note)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const insertSource = database.prepare(`
    INSERT INTO data_sources (id, source_type, name, vendor, ingest_channel, note)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const insertMetric = database.prepare(`
    INSERT INTO metric_catalog (
      code, label, short_label, category, default_unit, better_direction,
      normal_low, normal_high, reference_text, description
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertSet = database.prepare(`
    INSERT INTO measurement_sets (
      id, user_id, source_id, set_kind, title, recorded_at, report_date, note, raw_payload_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertMeasurement = database.prepare(`
    INSERT INTO measurements (
      id, measurement_set_id, metric_code, raw_value_text, value_numeric, unit,
      normalized_value, normalized_unit, reference_low, reference_high,
      abnormal_flag, note, source_label
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertGeneticFinding = database.prepare(`
    INSERT INTO genetic_findings (
      id, user_id, source_id, gene_symbol, variant_id, trait_code, risk_level,
      evidence_level, summary, suggestion, recorded_at, raw_payload_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertMeta = database.prepare(`
    INSERT INTO app_meta (key, value)
    VALUES (?, ?)
  `);

  database.exec("BEGIN");

  try {
    database.exec(`
      DELETE FROM report_snapshots;
      DELETE FROM rule_events;
      DELETE FROM measurements;
      DELETE FROM measurement_sets;
      DELETE FROM genetic_findings;
      DELETE FROM metric_catalog;
      DELETE FROM import_batches;
      DELETE FROM data_sources;
      DELETE FROM users;
      DELETE FROM app_meta;
    `);

    for (const user of users) {
      insertUser.run(
        user.id,
        user.displayName,
        user.sex,
        user.birthYear,
        user.heightCm,
        user.note ?? null
      );
    }

    for (const source of dataSources) {
      insertSource.run(
        source.id,
        source.sourceType,
        source.name,
        source.vendor ?? null,
        source.ingestChannel,
        source.note ?? null
      );
    }

    for (const metric of metricCatalog) {
      insertMetric.run(
        metric.code,
        metric.label,
        metric.shortLabel,
        metric.category,
        metric.defaultUnit,
        metric.betterDirection,
        metric.normalLow ?? null,
        metric.normalHigh ?? null,
        metric.referenceText ?? null,
        metric.description
      );
    }

    for (const set of measurementSets) {
      insertSet.run(
        set.id,
        "user-self",
        set.sourceId,
        set.kind,
        set.title,
        set.recordedAt,
        set.reportDate ?? null,
        set.note ?? null,
        JSON.stringify(set.rawPayload ?? {})
      );

      for (const item of set.measurements) {
        insertMeasurement.run(
          `${set.id}::${item.metricCode}`,
          set.id,
          item.metricCode,
          item.rawValue ?? String(item.value),
          item.value,
          item.unit,
          item.normalizedValue ?? item.value,
          item.normalizedUnit ?? item.unit,
          item.referenceLow ?? null,
          item.referenceHigh ?? null,
          item.abnormalFlag ?? "unknown",
          item.note ?? null,
          item.metricCode
        );
      }
    }

    for (const finding of geneticFindings) {
      insertGeneticFinding.run(
        finding.id,
        "user-self",
        finding.sourceId,
        finding.geneSymbol,
        finding.variantId,
        finding.traitCode,
        finding.riskLevel,
        finding.evidenceLevel,
        finding.summary,
        finding.suggestion,
        finding.recordedAt,
        JSON.stringify(finding.rawPayload ?? {})
      );
    }

    insertMeta.run("seed_version", SEED_VERSION);
    insertMeta.run("last_seeded_at", new Date().toISOString());

    database.exec("COMMIT");
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  }
}
