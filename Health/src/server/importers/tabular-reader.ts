import { readFileSync } from "node:fs";
import path from "node:path";

import * as XLSX from "xlsx";

import type { TabularReadResult } from "./types";

function parseCsv(content: string): string[][] {
  const rows: string[][] = [];
  let currentRow: string[] = [];
  let currentValue = "";
  let inQuotes = false;

  const pushValue = () => {
    currentRow.push(currentValue);
    currentValue = "";
  };

  const pushRow = () => {
    if (currentRow.length > 0 || currentValue.length > 0) {
      pushValue();
      rows.push(currentRow);
      currentRow = [];
    }
  };

  for (let index = 0; index < content.length; index += 1) {
    const character = content[index];
    const nextCharacter = content[index + 1];

    if (character === "\"") {
      if (inQuotes && nextCharacter === "\"") {
        currentValue += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (character === "," && !inQuotes) {
      pushValue();
      continue;
    }

    if ((character === "\n" || character === "\r") && !inQuotes) {
      if (character === "\r" && nextCharacter === "\n") {
        index += 1;
      }
      pushRow();
      continue;
    }

    currentValue += character;
  }

  pushRow();

  return rows
    .map((row) => row.map((value) => value.replace(/^\uFEFF/, "").trim()))
    .filter((row) => row.some((value) => value !== ""));
}

export function readTabularFile(filePath: string): TabularReadResult {
  const extension = path.extname(filePath).toLowerCase();

  if (![".csv", ".xlsx", ".xls"].includes(extension)) {
    throw new Error(
      `Unsupported file format: ${extension || "unknown"}. Supported formats: .csv, .xlsx, .xls`
    );
  }

  if (extension === ".csv") {
    const content = readFileSync(filePath, "utf8");
    const rows = parseCsv(content);
    const headers = rows[0] ?? [];
    const dataRows = rows.slice(1).map((row) =>
      Object.fromEntries(headers.map((header, index) => [header, row[index] ?? ""]))
    );

    return {
      filePath,
      sheetName: "csv",
      headers,
      rows: dataRows
    };
  }

  const workbook = XLSX.read(readFileSync(filePath), {
    type: "buffer",
    cellDates: true,
    dense: true
  });
  const sheetName = workbook.SheetNames[0];

  if (!sheetName) {
    throw new Error("No worksheet found in import file");
  }

  const sheet = workbook.Sheets[sheetName];
  const rows = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, {
    defval: "",
    raw: false,
    dateNF: "yyyy-mm-dd hh:mm:ss"
  });
  const headers = rows.length > 0 ? Object.keys(rows[0]) : [];

  return {
    filePath,
    sheetName,
    headers,
    rows: rows.map((row) =>
      Object.fromEntries(
        Object.entries(row).map(([key, value]) => [key, String(value ?? "")])
      )
    )
  };
}
