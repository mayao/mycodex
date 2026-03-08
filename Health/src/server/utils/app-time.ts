const APP_TIME_OFFSET = "+08:00";
const APP_TIME_OFFSET_MINUTES = 8 * 60;
const APP_TIME_OFFSET_MS = APP_TIME_OFFSET_MINUTES * 60 * 1000;

function pad(value: number): string {
  return value.toString().padStart(2, "0");
}

function formatShiftedDate(shifted: Date): string {
  return `${shifted.getUTCFullYear()}-${pad(shifted.getUTCMonth() + 1)}-${pad(shifted.getUTCDate())}`;
}

function toShiftedDate(input: Date | string): Date {
  const date = input instanceof Date ? input : new Date(input);

  if (!Number.isFinite(date.getTime())) {
    throw new RangeError(`Invalid date input: ${String(input)}`);
  }

  return new Date(date.getTime() + APP_TIME_OFFSET_MS);
}

export function formatAppDate(input: Date | string): string {
  if (typeof input === "string" && /^\d{4}-\d{2}-\d{2}$/.test(input)) {
    return input;
  }

  const shifted = toShiftedDate(input);

  return formatShiftedDate(shifted);
}

export function formatAppDateTimeIso(input: Date | string): string {
  const shifted = toShiftedDate(input);
  const date = formatShiftedDate(shifted);
  const hours = pad(shifted.getUTCHours());
  const minutes = pad(shifted.getUTCMinutes());
  const seconds = pad(shifted.getUTCSeconds());

  return `${date}T${hours}:${minutes}:${seconds}${APP_TIME_OFFSET}`;
}

export function addDaysToAppDate(dateString: string, days: number): string {
  const date = new Date(`${dateString}T00:00:00${APP_TIME_OFFSET}`);

  if (!Number.isFinite(date.getTime())) {
    throw new RangeError(`Invalid app date: ${dateString}`);
  }

  date.setUTCDate(date.getUTCDate() + days);

  return formatAppDate(date);
}

export function toStartOfAppDayIso(dateString: string): string {
  return `${dateString}T00:00:00${APP_TIME_OFFSET}`;
}

export function toEndOfAppDayIso(dateString: string): string {
  return `${dateString}T23:59:59${APP_TIME_OFFSET}`;
}

export function toStartOfAppDayTimestamp(dateString: string): number {
  return new Date(toStartOfAppDayIso(dateString)).getTime();
}

export function toEndOfAppDayTimestamp(dateString: string): number {
  return new Date(toEndOfAppDayIso(dateString)).getTime();
}

export function resolveAnalysisAsOf(
  latestSampleTime: string | undefined,
  now: Date = new Date()
): string {
  const currentAsOf = formatAppDateTimeIso(now);

  if (!latestSampleTime) {
    return currentAsOf;
  }

  const latestTimestamp = new Date(latestSampleTime).getTime();

  if (!Number.isFinite(latestTimestamp) || latestTimestamp > now.getTime()) {
    return currentAsOf;
  }

  return formatAppDateTimeIso(latestSampleTime);
}
