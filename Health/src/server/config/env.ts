import { z } from "zod";

const booleanFlagSchema = z
  .enum(["0", "1", "true", "false"])
  .optional()
  .transform((value) => value === "1" || value === "true");

const envSchema = z.object({
  HEALTH_LLM_PROVIDER: z.enum(["mock", "openai-compatible", "anthropic"]).optional(),
  HEALTH_LLM_MODEL: z.string().optional(),
  HEALTH_LLM_BASE_URL: z.string().url().optional().or(z.literal("").transform(() => undefined)),
  HEALTH_LLM_API_KEY: z.string().optional(),
  HEALTH_DATA_RETENTION_NOTE: z.string().optional(),
  HEALTH_IMPORT_AUDIT_MODE: z.enum(["redacted", "disabled"]).default("redacted"),
  HEALTH_ALLOW_LOCAL_EXPORTS: booleanFlagSchema,
  HEALTH_ALLOW_LOCAL_DELETE: booleanFlagSchema,
  HEALTH_LOG_LEVEL: z.enum(["silent", "error", "info"]).default("error"),
  HEALTH_AUTH_ENABLED: booleanFlagSchema,
  HEALTH_JWT_SECRET: z.string().min(16).optional().or(z.literal("").transform(() => undefined)),
});

export type AppEnv = z.infer<typeof envSchema>;

export function getAppEnv(): AppEnv {
  return envSchema.parse(process.env);
}
