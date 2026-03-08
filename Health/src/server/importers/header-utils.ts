const unitMap: Record<string, string> = {
  kg: "kg",
  公斤: "kg",
  g: "g",
  克: "g",
  lb: "lb",
  lbs: "lb",
  cm: "cm",
  厘米: "cm",
  m: "m",
  米: "m",
  km: "km",
  公里: "km",
  "%": "%",
  pct: "%",
  百分比: "%",
  "kg/m2": "kg/m2",
  "kg/m²": "kg/m2",
  "mmol/l": "mmol/L",
  "mg/dl": "mg/dL",
  "g/l": "g/L",
  "mg/l": "mg/L",
  "umol/l": "umol/L",
  "μmol/l": "umol/L",
  kcal: "kcal",
  千卡: "kcal",
  cal: "cal",
  分钟: "min",
  min: "min",
  mins: "min",
  minute: "min",
  分: "min",
  s: "s",
  sec: "s",
  secs: "s",
  秒: "s",
  h: "h",
  hr: "h",
  hrs: "h",
  小时: "h",
  bpm: "bpm",
  "次/分": "bpm",
  level: "level",
  count: "count",
  次: "count"
};

function normalizeUnitToken(unit: string): string {
  return unit.trim().toLowerCase().replace(/\s+/g, "");
}

function findHeaderBracketMatches(header: string) {
  return [...header.matchAll(/(?:（([^）]+)）|\(([^)]+)\))/g)].map((match) => ({
    index: match.index ?? -1,
    raw: match[0],
    value: (match[1] ?? match[2] ?? "").trim()
  }));
}

export function normalizeHeader(value: string): string {
  return value
    .trim()
    .replace(/（/g, "(")
    .replace(/）/g, ")")
    .replace(/\s+/g, "")
    .replace(/_/g, "")
    .replace(/-/g, "")
    .replace(/[.]/g, "")
    .toLowerCase();
}

export function stripHeaderUnit(header: string): string {
  const unitMatch = [...findHeaderBracketMatches(header)]
    .reverse()
    .find((match) => isRecognizedUnit(match.value));

  if (!unitMatch) {
    return header.trim();
  }

  return `${header.slice(0, unitMatch.index)}${header.slice(unitMatch.index + unitMatch.raw.length)}`
    .trim();
}

export function extractUnitFromHeader(header: string): string | undefined {
  const unitMatch = [...findHeaderBracketMatches(header)]
    .reverse()
    .find((match) => isRecognizedUnit(match.value));

  return unitMatch?.value;
}

export function isRecognizedUnit(unit: string | undefined): boolean {
  if (!unit) {
    return false;
  }

  return normalizeUnitToken(unit) in unitMap;
}

export function canonicalizeUnit(unit: string | undefined): string | undefined {
  if (!unit) {
    return undefined;
  }

  const normalized = normalizeUnitToken(unit);

  return unitMap[normalized] ?? unit.trim();
}
