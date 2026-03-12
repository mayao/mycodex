import { z } from "zod";

import { getAuthenticatedUserId, AuthError } from "../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../server/http/safe-response";
import {
  getPlanDashboard,
  acceptSuggestion,
  manualCheckIn,
  updatePlanItemStatus,
  updatePlanItem
} from "../../../server/services/health-plan-service";

export const dynamic = "force-dynamic";

/**
 * GET /api/health-plans — Plan dashboard (items + suggestions + stats)
 */
export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    return jsonOk(await getPlanDashboard(userId));
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/health-plans", method: "GET" } });
    }
    return jsonSafeError({
      message: "健康计划数据暂时不可用。",
      error,
      context: { route: "/api/health-plans", method: "GET" }
    });
  }
}

const acceptSchema = z.object({
  action: z.literal("accept"),
  suggestion_id: z.string().min(1),
  target_value: z.number().optional(),
  target_unit: z.string().optional(),
  frequency: z.enum(["daily", "weekly", "once"]).optional(),
  time_hint: z.string().optional(),
});

const checkInSchema = z.object({
  action: z.literal("check_in"),
  plan_item_id: z.string().min(1),
  date: z.string().optional()
});

const updateStatusSchema = z.object({
  action: z.literal("update_status"),
  plan_item_id: z.string().min(1),
  status: z.enum(["active", "paused", "completed", "archived"])
});

const updateItemSchema = z.object({
  action: z.literal("update_item"),
  plan_item_id: z.string().min(1),
  target_value: z.number().optional(),
  target_unit: z.string().optional(),
  frequency: z.enum(["daily", "weekly", "once"]).optional(),
  time_hint: z.string().optional(),
});

const postBodySchema = z.discriminatedUnion("action", [
  acceptSchema,
  checkInSchema,
  updateStatusSchema,
  updateItemSchema
]);

/**
 * POST /api/health-plans — Accept suggestion, manual check-in, or update status
 */
export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const body = postBodySchema.parse(await request.json());

    switch (body.action) {
      case "accept": {
        const overrides = {
          target_value: body.target_value,
          target_unit: body.target_unit,
          frequency: body.frequency,
          time_hint: body.time_hint,
        };
        const hasOverrides = Object.values(overrides).some(v => v !== undefined);
        const item = acceptSuggestion(userId, body.suggestion_id, hasOverrides ? overrides : undefined);
        return jsonOk({ plan_item: item });
      }
      case "check_in": {
        const check = manualCheckIn(userId, body.plan_item_id, body.date);
        return jsonOk({ check });
      }
      case "update_status": {
        const item = updatePlanItemStatus(userId, body.plan_item_id, body.status);
        return jsonOk({ plan_item: item });
      }
      case "update_item": {
        const item = updatePlanItem(userId, body.plan_item_id, {
          target_value: body.target_value,
          target_unit: body.target_unit,
          frequency: body.frequency,
          time_hint: body.time_hint,
        });
        return jsonOk({ plan_item: item });
      }
    }
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/health-plans", method: "POST" } });
    }
    const message = error instanceof Error ? error.message : "操作失败";
    return jsonSafeError({
      message,
      status: 400,
      error,
      context: { route: "/api/health-plans", method: "POST" }
    });
  }
}
