INSERT OR REPLACE INTO insight_record (
  id,
  user_id,
  metric_code,
  category,
  insight_type,
  severity,
  title,
  summary,
  source_type,
  source_file,
  related_record_ids,
  disclaimer,
  created_at,
  notes
)
VALUES
(
  'insight::lpa-long-term-watch',
  'user-self',
  'lipid.lpa',
  'lipid',
  'rule',
  'attention',
  'Lp(a) 作为长期背景指标持续待关注',
  'mock 数据显示 2026-01-04、2026-01-19、2026-02-11 三次血脂专项中 Lp(a) 均高于 30 mg/dL，更适合作为长期背景风险标签持续跟踪。',
  'rule_engine',
  'stage2-migration',
  'record::lipid-panel-2026-01-04::lipid.lpa,record::lipid-panel-2026-01-19::lipid.lpa,record::lipid-panel-2026-02-11::lipid.lpa',
  '非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。',
  '2026-03-08T10:00:00+08:00',
  '用于验证 insight_record 结构。'
),
(
  'insight::body-composition-positive',
  'user-self',
  'body.body_fat_pct',
  'body_composition',
  'rule',
  'positive',
  '体脂下降且骨骼肌率未下降',
  'mock 数据显示从 2025-11-23 到 2026-03-06，体脂率下降而骨骼肌率保持稳定，适合在趋势层展示为积极信号。',
  'rule_engine',
  'stage2-migration',
  'record::body-comp-2025-11-23::body.body_fat_pct,record::body-comp-2026-03-06::body.body_fat_pct',
  '非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。',
  '2026-03-08T10:05:00+08:00',
  '用于验证 insight_record 结构。'
),
(
  'insight::activity-consistency',
  'user-self',
  'activity.exercise_minutes',
  'activity',
  'rule',
  'positive',
  '运动执行度较稳定',
  '近 14 天活动 mock 数据可以支持训练分钟、活动能量和站立时长的联动分析。',
  'rule_engine',
  'stage2-migration',
  'record::activity-2026-03-04::activity.exercise_minutes,record::activity-2026-03-08::activity.exercise_minutes',
  '非医疗诊断：以下内容仅用于健康数据整理、趋势解释与生活方式管理，不替代医生判断。',
  '2026-03-08T10:10:00+08:00',
  '用于验证 insight_record 结构。'
);

INSERT OR REPLACE INTO report_snapshot (
  id,
  user_id,
  report_type,
  period_start,
  period_end,
  summary_json,
  source_type,
  created_at,
  notes
)
VALUES
(
  'report::weekly::2026-03-08',
  'user-self',
  'weekly',
  '2026-03-02',
  '2026-03-08',
  '{"focus":["lipid","body_composition","activity"],"key_points":["LDL-C 维持较低","体重与体脂继续下行","训练分钟保持稳定"],"disclaimer":"非医疗诊断"}',
  'report_engine',
  '2026-03-08T11:00:00+08:00',
  '用于验证 report_snapshot 结构。'
),
(
  'report::monthly::2026-03',
  'user-self',
  'monthly',
  '2026-02-01',
  '2026-02-29',
  '{"focus":["lipid","body_composition"],"key_points":["Lp(a) 持续偏高需长期跟踪","体脂秤趋势显示体脂下降"],"disclaimer":"非医疗诊断"}',
  'report_engine',
  '2026-03-08T11:05:00+08:00',
  '用于验证 report_snapshot 结构。'
);
