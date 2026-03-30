INSERT OR IGNORE INTO data_source (
  id,
  user_id,
  source_type,
  source_name,
  vendor,
  ingest_channel,
  source_file,
  notes,
  created_at,
  updated_at,
  origin_server_id
)
SELECT
  gf.source_id,
  COALESCE(gf.user_id, 'user-self'),
  COALESCE(ds.source_type, 'genetic_report'),
  COALESCE(ds.name, '基因报告'),
  ds.vendor,
  COALESCE(ds.ingest_channel, 'document'),
  NULL,
  COALESCE(ds.note, 'Migrated from legacy genetic source'),
  COALESCE(ds.created_at, CURRENT_TIMESTAMP),
  CURRENT_TIMESTAMP,
  (SELECT value FROM app_meta WHERE key = 'server_id')
FROM genetic_findings AS gf
LEFT JOIN data_sources AS ds
  ON ds.id = gf.source_id
LEFT JOIN data_source AS uds
  ON uds.id = gf.source_id
WHERE uds.id IS NULL;

ALTER TABLE genetic_findings RENAME TO genetic_findings_legacy;

CREATE TABLE genetic_findings (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id),
  source_id TEXT NOT NULL REFERENCES data_source(id),
  gene_symbol TEXT NOT NULL,
  variant_id TEXT NOT NULL,
  trait_code TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  evidence_level TEXT NOT NULL,
  summary TEXT NOT NULL,
  suggestion TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  raw_payload_json TEXT
);

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
SELECT
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
FROM genetic_findings_legacy;

DROP TABLE genetic_findings_legacy;
