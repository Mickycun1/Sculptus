import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { z } from "zod";
import type { SavedMeal } from "./mealStore.js";

const FoodSchema = z.object({
  name: z.string(),
  calories: z.number().int(),
  caloriesLow: z.number().int(),
  caloriesHigh: z.number().int(),
  proteinGrams: z.number(),
  assumption: z.string()
});

const DayLogSchema = z.object({
  foods: z.array(FoodSchema),
  considering: z.array(FoodSchema),
  workouts: z.array(
    z.object({
      name: z.string(),
      caloriesBurned: z.number().int(),
      estimatedCaloriesBurned: z.number().int(),
      minutes: z.number().int(),
      details: z.string()
    })
  ),
  steps: z.number().int().nullable(),
  weightLb: z.number().nullable(),
  question: z.string().nullable()
});

export type DayLog = z.infer<typeof DayLogSchema>;

const MealEstimateSchema = z.object({
  name: z.string(),
  calories: z.number().int(),
  proteinGrams: z.number(),
  items: z.array(
    z.object({
      name: z.string(),
      calories: z.number().int(),
      proteinGrams: z.number()
    })
  ),
  assumption: z.string()
});

export type MealEstimate = z.infer<typeof MealEstimateSchema>;

export type LogImage = {
  mediaType: "image/jpeg" | "image/png" | "image/webp";
  data: string;
};

const MEAL_PROMPT = `You estimate the nutrition of one meal a person makes regularly, from its name and ingredient list, for a calorie tracking app.

- items: one entry per ingredient with the quantity folded into the name ("200g chicken thigh, cooked"), its calories and protein.
- The list is a whole meal-prep batch. Every quantity is for the whole batch ("7 chicken breasts" means all 7). Never divide anything into servings: the app divides by the portion count itself.
- items: each ingredient at its full listed quantity. calories and proteinGrams are the sum of all items, for the whole batch.
- If quantities are missing, assume a typical home portion and say so briefly in assumption; otherwise assumption is an empty string.
- name: the person's name for the meal if given, otherwise a short natural name.`;

const SYSTEM_PROMPT = `You turn a person's casual daily log into structured nutrition and activity data for a calorie tracking app.

Foods:
- One entry per distinct food or meal, with the quantity folded into the name ("3 bananas", "600g homemade chicken vegetable soup").
- calories is your single best estimate; caloriesLow and caloriesHigh bound a realistic range. Keep the range tight for packaged or weighed foods and wider for restaurant meals or vague portions.
- If the person states a calorie figure for an item (a label, "15 cals a mint"), use it as the estimate.
- proteinGrams is your best protein estimate.
- assumption is a short note on anything you assumed that materially changes the number ("0% Greek yogurt", "pasta weighed dry"), or an empty string.
- Shared meals ("between 2", "split with my wife"): log only the person's share, with the share in the name ("Half of egg and sourdough dinner for 2"), and give the whole meal's calories in assumption ("your half of a ~1,640 kcal meal").

Considering:
- Foods the person has not eaten yet but is weighing up ("if I have popcorn", "thinking about yogurt and whey", "should I have...") go in considering, never in foods. Use the same fields as foods. Group items they would eat together into one entry ("200g Greek yogurt + 1/2 scoop whey"). Empty when nothing is being considered.

Activity:
- workouts: caloriesBurned is only a burn the person reports (watch, WHOOP, machine), otherwise 0.
- estimatedCaloriesBurned: when the person describes the actual work (a pasted WOD, movements, loads, reps, rounds, distances, time cap or finish time), estimate the calories that work burned for their body weight, counting only working time plus a modest allowance for warm-up and rest. Be conservative: wrist trackers often over-read strength and gymnastics work. If the work is not described in enough detail to estimate, use 0.
- details is a one-line summary of the work done ("5 rounds: 400m run, 15 thrusters @ 95 lb; 18:40"), or an empty string.
- minutes is the duration if stated or clear from the workout, otherwise 0.
- steps is the step count if mentioned ("12k steps" is 12000), otherwise null.
- weightLb is a morning weigh-in in pounds if mentioned (convert kg), otherwise null.

question: ask one short question only when a single item's uncertainty could move the day's total by 100 kcal or more, and the answer is something the person can easily check. Say how much the answer changes the total ("Was the egg white carton 16 or 32 oz? That changes your half by about 125 kcal."). Otherwise null. Never ask more than one.

Saved meals: the person may have saved meals with known numbers. When the log mentions one, even loosely ("my usual yogurt bowl"), use its calories and protein exactly, scaled for the portion ("half my Mexican bowl"), keep a tight range, and note "saved meal" in assumption. Only add on top of it for extras they mention.

Photos: the person may attach photos, such as a photo of their plate or meal, a food label, a Wodify or gym app screenshot, or a whiteboard. Read them as part of the log. For a photo of food, identify each food, estimate the portion from the plate and anything in the picture for scale, log one entry per food with a wider range, and note the portion you assumed. For a workout photo, put the WOD in details and estimate the burn from the work and any result shown (time, rounds, loads). If no result is visible, assume they finished it as written at an average pace, say so in details, and ask for their time or loads in question.

Ignore commentary, feelings, and anything that is not food, activity, or weight.`;

export type CallUsage = {
  route: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
};

type UsageLike = {
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
};

function toUsage(route: string, model: string, usage: UsageLike): CallUsage {
  return {
    route,
    model,
    inputTokens: usage.input_tokens ?? 0,
    outputTokens: usage.output_tokens ?? 0,
    cacheReadTokens: usage.cache_read_input_tokens ?? 0,
    cacheWriteTokens: usage.cache_creation_input_tokens ?? 0
  };
}

export class LogParser {
  private readonly client: Anthropic;

  constructor(
    apiKey: string,
    private readonly onUsage: (usage: CallUsage, userId: string) => void = () => {}
  ) {
    this.client = new Anthropic({ apiKey });
  }

  async parse(
    text: string,
    savedMeals: SavedMeal[] = [],
    bodyWeightLb: number | null = null,
    images: LogImage[] = [],
    userId = ""
  ): Promise<DayLog> {
    const context = [
      bodyWeightLb ? `Body weight: ${bodyWeightLb} lb` : "",
      savedMeals.length ? `Saved meals:\n${JSON.stringify(savedMeals)}` : ""
    ].filter(Boolean);
    const prompt = context.length
      ? `${context.join("\n\n")}\n\nLog:\n${text || "(see photos)"}`
      : text || "(see photos)";
    const content = [
      ...images.map((image) => ({
        type: "image" as const,
        source: {
          type: "base64" as const,
          media_type: image.mediaType,
          data: image.data
        }
      })),
      { type: "text" as const, text: prompt }
    ];
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
      messages: [{ role: "user", content }]
    });
    this.onUsage(toUsage(images.length ? "log-photo" : "log", response.model, response.usage), userId);

    if (response.stop_reason === "refusal") {
      throw new Error("Could not read that log. Try rephrasing it.");
    }
    if (!response.parsed_output) {
      throw new Error("Could not read that log.");
    }
    return response.parsed_output;
  }

  async estimateMeal(
    name: string,
    ingredients: string,
    portions = 1,
    userId = ""
  ): Promise<MealEstimate> {
    const response = await this.client.beta.messages.parse({
      model: "claude-opus-5-5",
      max_tokens: 8000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: {
        effort: "medium",
        format: betaZodOutputFormat(MealEstimateSchema)
      },
      system: MEAL_PROMPT,
      messages: [
        {
          role: "user",
          content: `Meal name: ${name || "(none)"}\nThe batch makes ${portions} portion(s); return totals for the whole batch.\nIngredients:\n${ingredients}`
        }
      ]
    });
    this.onUsage(toUsage("meal-estimate", response.model, response.usage), userId);
    if (!response.parsed_output) {
      throw new Error("Could not work out that meal. Try listing amounts.");
    }
    return response.parsed_output;
  }
}
