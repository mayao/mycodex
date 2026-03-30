import type { DatabaseSync } from "node:sqlite";

import { importerSpecs } from "./specs";
import { executeTabularImport } from "./tabular-importer";
import type { ImportExecutionResult, ImportRequest, Importer, ImporterKey } from "./types";

function createImporter(key: ImporterKey): Importer {
  const spec = importerSpecs[key];

  return {
    key,
    spec,
    import(database: DatabaseSync, request: ImportRequest): ImportExecutionResult {
      return executeTabularImport(database, spec, request);
    }
  };
}

export const annualExamImporter = createImporter("annual_exam");
export const bloodTestImporter = createImporter("blood_test");
export const bodyScaleImporter = createImporter("body_scale");
export const activityImporter = createImporter("activity");
export const geneticImporter = createImporter("genetic");
export const dietImporter = createImporter("diet");

export const importers: Record<ImporterKey, Importer> = {
  annual_exam: annualExamImporter,
  blood_test: bloodTestImporter,
  body_scale: bodyScaleImporter,
  activity: activityImporter,
  genetic: geneticImporter,
  diet: dietImporter
};
