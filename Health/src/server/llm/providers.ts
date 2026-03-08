import { z } from "zod";

import type {
  HealthSummaryGenerationResult,
  HealthSummaryPromptBundle,
  HealthSummarySectionedOutput,
  NarrativeProviderKind
} from "../domain/health-hub";

export const healthSummaryOutputSchema = z.object({
  headline: z.string().min(1),
  most_important_changes: z.array(z.string().min(1)),
  possible_reasons: z.array(z.string().min(1)),
  priority_actions: z.array(z.string().min(1)),
  continue_observing: z.array(z.string().min(1)),
  disclaimer: z.string().min(1)
});

export interface HealthSummaryProviderRequest {
  prompt: HealthSummaryPromptBundle;
  periodKind: HealthSummarySectionedOutput["period_kind"];
  fallback: HealthSummarySectionedOutput;
}

export interface HealthSummaryProvider {
  kind: NarrativeProviderKind;
  model: string;
  generate(request: HealthSummaryProviderRequest): Promise<HealthSummaryGenerationResult>;
}

export class MockHealthSummaryProvider implements HealthSummaryProvider {
  kind: NarrativeProviderKind = "mock";
  model = "mock-health-summary-v1";

  async generate(
    request: HealthSummaryProviderRequest
  ): Promise<HealthSummaryGenerationResult> {
    return {
      provider: this.kind,
      model: this.model,
      prompt: request.prompt,
      output: request.fallback
    };
  }
}

interface OpenAICompatibleProviderOptions {
  apiKey: string;
  baseUrl: string;
  model: string;
}

export class OpenAICompatibleHealthSummaryProvider implements HealthSummaryProvider {
  kind: NarrativeProviderKind = "openai-compatible";
  model: string;
  private apiKey: string;
  private baseUrl: string;

  constructor(options: OpenAICompatibleProviderOptions) {
    this.apiKey = options.apiKey;
    this.baseUrl = options.baseUrl.replace(/\/$/, "");
    this.model = options.model;
  }

  async generate(
    request: HealthSummaryProviderRequest
  ): Promise<HealthSummaryGenerationResult> {
    const response = await fetch(`${this.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`
      },
      body: JSON.stringify({
        model: this.model,
        temperature: 0.2,
        messages: [
          {
            role: "system",
            content: request.prompt.systemPrompt
          },
          {
            role: "user",
            content: request.prompt.userPrompt
          }
        ]
      })
    });

    if (!response.ok) {
      throw new Error("LLM provider request failed");
    }

    const payload = (await response.json()) as {
      choices?: Array<{
        message?: {
          content?: string;
        };
      }>;
    };
    const rawContent = payload.choices?.[0]?.message?.content;

    if (!rawContent) {
      throw new Error("LLM provider returned empty content");
    }

    const parsed = healthSummaryOutputSchema.parse(JSON.parse(rawContent));

    return {
      provider: this.kind,
      model: this.model,
      prompt: request.prompt,
      output: {
        period_kind: request.periodKind,
        ...parsed
      }
    };
  }
}
