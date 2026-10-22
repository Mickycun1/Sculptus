import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { z } from "zod";

const DayLogSchema = z.object({
  foods: z.array(
    z.object({
      name: z.string(),
      calories: z.number().int(),
      caloriesLow: z.number().int(),
      caloriesHigh: z.number().int(),
      proteinGrams: z.number(),
      assumption: z.string()
    })
  ),
  workouts: z.array(
    z.object({
      name: z.string(),
      caloriesBurned: z.number().int(),
      minutes: z.number().int()
    })
  ),
  steps: z.number().int().nullable(),
  weightLb: z.number().nullable(),
  question: z.string().nullable()
});

export type DayLog = z.infer<typeof DayLogSchema>;

const SYSTEM_PROMPT = `You turn a person's casual daily log into structured nutrition and activity data for a calorie tracking app.

Foods:
- One entry per distinct food or meal, with the quantity folded into the name ("3 bananas", "600g homemade chicken vegetable soup").
- calories is your single best estimate; caloriesLow and caloriesHigh bound a realistic range. Keep the range tight for packaged or weighed foods and wider for restaurant meals or vague portions.
- If the person states a calorie figure for an item (a label, "15 cals a mint"), use it as the estimate.
- proteinGrams is your best protein estimate.
- assumption is a short note on anything you assumed that materially changes the number ("0% Greek yogurt", "pasta weighed dry"), or an empty string.

Activity:
- workouts holds only calorie burns the person reports (watch, WHOOP, machine). Never estimate a burn yourself; if a workout is described without a number, record caloriesBurned as 0.
- steps is the step count if mentioned ("12k steps" is 12000), otherwise null.
- weightLb is a morning weigh-in in pounds if mentioned (convert kg), otherwise null.

question: ask one short question only when a single item's uncertainty could move the day's total by 200 kcal or more, and the answer is something the person can easily check. Otherwise null. Never ask more than one.

Ignore commentary, feelings, and anything that is not food, activity, or weight.`;

export class LogParser {
  private readonly client: Anthropic;

  constructor(apiKey: string) {
    this.client = new Anthropic({ apiKey });
  }

  async parse(text: string): Promise<DayLog> {
    const response = await this.client.beta.messages.parse({
      model: "claude-opus-5-5",
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: {
        effort: "medium",
        format: betaZodOutputFormat(DayLogSchema)
      },
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: text }]
    });

    if (response.stop_reason === "refusal") {
      throw new Error("Could not read that log. Try rephrasing it.");
    }
    if (!response.parsed_output) {
      throw new Error("Could not read that log.");
    }
    return response.parsed_output;
  }
}
