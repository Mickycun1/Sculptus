import { config } from "./config.js";
import { TokenStore, WhoopTokens } from "./tokenStore.js";

const whoopAuthUrl = "https://api.prod.whoop.com/oauth/oauth2/auth";
const whoopTokenUrl = "https://api.prod.whoop.com/oauth/oauth2/token";
const whoopApiBase = "https://api.prod.whoop.com/developer";

type JsonObject = Record<string, unknown>;

function recordsOf(value: unknown): JsonObject[] {
  if (!value || typeof value !== "object") {
    return [];
  }
  const records = (value as JsonObject).records;
  return Array.isArray(records)
    ? records.filter((item): item is JsonObject => !!item && typeof item === "object")
    : [];
}

function objectOf(value: unknown): JsonObject {
  return value && typeof value === "object" ? (value as JsonObject) : {};
}

function numberOf(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function stringOf(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function dateBounds(date: string) {
  const start = new Date(`${date}T00:00:00.000Z`);
  const end = new Date(start);
  end.setUTCDate(start.getUTCDate() + 1);
  return {
    start: start.toISOString(),
    end: end.toISOString()
  };
}

const stepKeys = new Set([
  "steps",
  "stepcount",
  "stepstotal",
  "totalsteps",
  "dailysteps",
  "step_count",
  "steps_count",
  "step_count_total",
  "total_step_count",
  "daily_step_count"
]);

function normalizedKey(key: string) {
  return key.toLowerCase().replace(/[^a-z0-9_]/g, "");
}

function findStepCandidate(
  value: unknown,
  source: string,
  path: string[] = []
): { steps: number; source: string } | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  if (Array.isArray(value)) {
    for (const [index, item] of value.entries()) {
      const found = findStepCandidate(item, source, [...path, String(index)]);
      if (found) {
        return found;
      }
    }
    return null;
  }

  for (const [key, nestedValue] of Object.entries(value as JsonObject)) {
    if (stepKeys.has(normalizedKey(key))) {
      const steps = numberOf(nestedValue);
      if (steps > 0) {
        return {
          steps: Math.round(steps),
          source: `${source}.${[...path, key].join(".")}`
        };
      }
    }
  }

  for (const [key, nestedValue] of Object.entries(value as JsonObject)) {
    const found = findStepCandidate(nestedValue, source, [...path, key]);
    if (found) {
      return found;
    }
  }

  return null;
}

function findDailySteps(
  sources: Array<{ name: string; payload: unknown }>
): { steps: number; source: string } {
  for (const source of sources) {
    const found = findStepCandidate(source.payload, source.name);
    if (found) {
      return found;
    }
  }

  return {
    steps: 0,
    source: "not_available_in_official_whoop_api"
  };
}

function tokenFromResponse(payload: JsonObject): WhoopTokens {
  const expiresIn = numberOf(payload.expires_in);
  return {
    accessToken: stringOf(payload.access_token),
    refreshToken: stringOf(payload.refresh_token),
    expiresAt: Date.now() + Math.max(expiresIn - 60, 60) * 1000,
    scope: stringOf(payload.scope),
    tokenType: stringOf(payload.token_type) || "bearer"
  };
}

export class WhoopClient {
  constructor(private readonly tokenStore: TokenStore) {}

  buildAuthorizationUrl(state: string) {
    const url = new URL(whoopAuthUrl);
    url.searchParams.set("client_id", config.whoopClientId);
    url.searchParams.set("redirect_uri", config.whoopRedirectUri);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("scope", config.whoopScopes.join(" "));
    url.searchParams.set("state", state);
    return url.toString();
  }

  async exchangeCode(userKey: string, code: string) {
    const body = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: config.whoopRedirectUri,
      client_id: config.whoopClientId,
      client_secret: config.whoopClientSecret
    });

    const response = await fetch(whoopTokenUrl, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body
    });
    const payload = (await response.json()) as JsonObject;
    if (!response.ok) {
      throw new Error(`WHOOP token exchange failed: ${JSON.stringify(payload)}`);
    }

    const tokens = tokenFromResponse(payload);
    await this.tokenStore.set(userKey, tokens);
    return tokens;
  }

  async revoke(userKey: string) {
    const accessToken = await this.getAccessToken(userKey);
    const response = await fetch(`${whoopApiBase}/v2/user/access`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${accessToken}` }
    });
    if (!response.ok && response.status !== 401) {
      throw new Error(`WHOOP revoke failed with HTTP ${response.status}`);
    }
    await this.tokenStore.clear(userKey);
  }

  async dailySummary(userKey: string, date: string) {
    const accessToken = await this.getAccessToken(userKey);
    const { start, end } = dateBounds(date);
    const [profile, body, recoveries, sleeps, cycles, workouts] =
      await Promise.all([
        this.get(accessToken, "/v2/user/profile/basic"),
        this.get(accessToken, "/v2/user/measurement/body"),
        this.get(accessToken, "/v2/recovery", { start, end, limit: "1" }),
        this.get(accessToken, "/v2/activity/sleep", { start, end, limit: "1" }),
        this.get(accessToken, "/v2/cycle", { start, end, limit: "1" }),
        this.get(accessToken, "/v2/activity/workout", {
          start,
          end,
          limit: "25"
        })
      ]);

    const recovery = recordsOf(recoveries)[0] ?? {};
    const recoveryScore = objectOf(recovery.score);
    const sleep = recordsOf(sleeps)[0] ?? {};
    const sleepScore = objectOf(sleep.score);
    const stageSummary = objectOf(sleepScore.stage_summary);
    const cycle = recordsOf(cycles)[0] ?? {};
    const cycleScore = objectOf(cycle.score);
    const workoutRecords = recordsOf(workouts);
    const latestWorkout = workoutRecords[0] ?? {};
    const latestWorkoutScore = objectOf(latestWorkout.score);

    const workoutKilojoules = workoutRecords.reduce(
      (sum, workout) => sum + numberOf(objectOf(workout.score).kilojoule),
      0
    );
    const todayWorkoutMinutes = workoutRecords.reduce((sum, workout) => {
      const startedAt = Date.parse(stringOf(workout.start));
      const endedAt = Date.parse(stringOf(workout.end));
      if (!Number.isFinite(startedAt) || !Number.isFinite(endedAt)) {
        return sum;
      }
      return sum + Math.max(Math.round((endedAt - startedAt) / 60000), 0);
    }, 0);

    const sleepMillis =
      numberOf(stageSummary.total_light_sleep_time_milli) +
      numberOf(stageSummary.total_slow_wave_sleep_time_milli) +
      numberOf(stageSummary.total_rem_sleep_time_milli);
    const profileObject = objectOf(profile);
    const profileName =
      [profileObject.first_name, profileObject.last_name]
        .map(stringOf)
        .filter(Boolean)
        .join(" ") || stringOf(profileObject.name);
    const bodyObject = objectOf(body);
    const bodyWeightKg =
      numberOf(bodyObject.weight_kilogram) ||
      numberOf(bodyObject.weight_kg) ||
      numberOf(bodyObject.weight);
    const dailySteps = findDailySteps([
      { name: "cycle", payload: cycle },
      { name: "workouts", payload: workoutRecords },
      { name: "body", payload: body },
      { name: "profile", payload: profile }
    ]);

    return {
      connected: true,
      summaryDate: date,
      profileName,
      profileEmail: stringOf(profileObject.email),
      lastSyncedAt: new Date().toISOString(),
      recoveryScore: Math.round(numberOf(recoveryScore.recovery_score)),
      hrvRmssdMillis: numberOf(recoveryScore.hrv_rmssd_milli),
      restingHeartRate: Math.round(numberOf(recoveryScore.resting_heart_rate)),
      sleepPerformance: Math.round(
        numberOf(sleepScore.sleep_performance_percentage)
      ),
      sleepHours: sleepMillis / 3600000,
      cycleStrain: numberOf(cycleScore.strain),
      cycleKilojoules: numberOf(cycleScore.kilojoule),
      todayWorkoutCalories: Math.round(workoutKilojoules * 0.239006),
      todayWorkoutCount: workoutRecords.length,
      todayWorkoutMinutes,
      latestWorkoutName: stringOf(latestWorkout.sport_name),
      latestWorkoutStart: stringOf(latestWorkout.start),
      latestWorkoutStrain: numberOf(latestWorkoutScore.strain),
      latestWorkoutKilojoules: numberOf(latestWorkoutScore.kilojoule),
      bodyWeightKg,
      bodyWeightLb: bodyWeightKg > 0 ? bodyWeightKg * 2.2046226218 : 0,
      steps: dailySteps.steps,
      stepsSource: dailySteps.source,
      stepsRecordedAt: new Date().toISOString()
    };
  }

  private async getAccessToken(userKey: string) {
    const tokens = await this.tokenStore.get(userKey);
    if (!tokens) {
      throw new Error("WHOOP is not connected.");
    }
    if (tokens.expiresAt > Date.now()) {
      return tokens.accessToken;
    }

    const refreshed = await this.refresh(tokens.refreshToken);
    await this.tokenStore.set(userKey, refreshed);
    return refreshed.accessToken;
  }

  private async refresh(refreshToken: string) {
    const body = new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: config.whoopClientId,
      client_secret: config.whoopClientSecret,
      scope: "offline"
    });
    const response = await fetch(whoopTokenUrl, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body
    });
    const payload = (await response.json()) as JsonObject;
    if (!response.ok) {
      throw new Error(`WHOOP token refresh failed: ${JSON.stringify(payload)}`);
    }
    return tokenFromResponse(payload);
  }

  private async get(
    accessToken: string,
    path: string,
    query: Record<string, string> = {}
  ) {
    const url = new URL(`${whoopApiBase}${path}`);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }

    const response = await fetch(url, {
      headers: { authorization: `Bearer ${accessToken}` }
    });
    const payload = response.status === 204 ? {} : ((await response.json()) as JsonObject);
    if (!response.ok) {
      throw new Error(`WHOOP ${path} failed: ${JSON.stringify(payload)}`);
    }
    return payload;
  }
}
