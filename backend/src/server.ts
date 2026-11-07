import cors from "cors";
import express from "express";
import crypto from "node:crypto";
import { OAuth2Client } from "google-auth-library";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { type AppUser, createAuthStore } from "./authStore.js";
import { assertWhoopConfig, config } from "./config.js";
import { type LogImage, LogParser } from "./logParser.js";
import { Mailer } from "./mailer.js";
import { createPasswordStore } from "./passwordStore.js";
import { createMealStore } from "./mealStore.js";
import { costOf, createUsageStore } from "./usageStore.js";
import { Billing, createBillingStore } from "./billing.js";
import { SubscriptionChecker } from "./subscription.js";
import { createTokenStore } from "./tokenStore.js";
import { WhoopClient } from "./whoopClient.js";

const app = express();
app.set("trust proxy", 1);
app.use(cors());
app.post(
  "/api/stripe/webhook",
  express.raw({ type: "application/json" }),
  async (request, response) => {
    try {
      await billing.handleWebhook(
        request.body as Buffer,
        String(request.headers["stripe-signature"] ?? "")
      );
      response.json({ received: true });
    } catch (error) {
      console.error("stripe webhook failed", error);
      response.status(400).json({ error: "Invalid webhook." });
    }
  }
);
app.use(express.json({ limit: "12mb" }));

const oauthStates = new Map<string, { userId: string; expiresAt: number }>();
const authStore = await createAuthStore(config.mongoUri, config.mongoDbName);
const tokenStore = await createTokenStore(config.mongoUri, config.mongoDbName);
const whoop = new WhoopClient(tokenStore);
const mealStore = await createMealStore(config.mongoUri, config.mongoDbName);
const passwordStore = await createPasswordStore(config.mongoUri, config.mongoDbName);
const mailer = new Mailer(config.resendApiKey, config.mailFrom);
const attempts = new Map<string, { count: number; resetAt: number }>();

function tooManyAttempts(key: string, limit: number, windowMinutes: number) {
  const now = Date.now();
  const entry = attempts.get(key);
  if (!entry || entry.resetAt < now) {
    attempts.set(key, { count: 1, resetAt: now + windowMinutes * 60 * 1000 });
    return false;
  }
  entry.count += 1;
  return entry.count > limit;
}

function readEmail(request: express.Request) {
  const email = String(request.body?.email ?? "").trim().toLowerCase();
  return email.includes("@") && email.length <= 254 ? email : "";
}

function readPassword(request: express.Request) {
  return String(request.body?.password ?? "");
}

const passwordRule = "Use at least 8 characters for your password.";

function readImages(value: unknown): LogImage[] | null {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > 3) {
    return null;
  }
  const images: LogImage[] = [];
  for (const item of value) {
    const mediaType = String(item?.mediaType ?? "");
    const data = String(item?.data ?? "");
    if (
      !["image/jpeg", "image/png", "image/webp"].includes(mediaType) ||
      !data ||
      data.length > 4_000_000
    ) {
      return null;
    }
    images.push({ mediaType: mediaType as LogImage["mediaType"], data });
  }
  return images;
}
const googleClient = new OAuth2Client(config.googleWebClientId || undefined);
const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys")
);
const usageStore = await createUsageStore(config.mongoUri, config.mongoDbName);
const billing = new Billing(
  config.stripeSecretKey,
  config.stripePriceId,
  config.stripeWebhookSecret,
  config.publicUrl,
  await createBillingStore(config.mongoUri, config.mongoDbName)
);
const subscriptions = new SubscriptionChecker(
  billing,
  new Set(config.subscriptionExemptUserIds)
);

async function requireSubscription(user: AppUser, response: express.Response) {
  if (await subscriptions.isActive(user.id)) {
    return true;
  }
  response.status(402).json({ error: "Your Sculptus subscription isn't active." });
  return false;
}
const logParser = new LogParser(config.anthropicApiKey, (usage, userId) => {
  const record = { ...usage, userId, costUsd: costOf(usage.model, usage), at: new Date() };
  console.log(JSON.stringify({ event: "ai_usage", ...record }));
  usageStore.record(record).catch((error) => console.error("usage record failed", error));
});

function newOauthState() {
  return crypto.randomBytes(16).toString("hex");
}

function handleError(error: unknown, response: express.Response) {
  const message = error instanceof Error ? error.message : "Unexpected error";
  const status = message.includes("not connected") ? 409 : 500;
  response.status(status).json({ error: message });
}

function bearerToken(request: express.Request) {
  const authorization = request.header("authorization") ?? "";
  const [scheme, token] = authorization.split(" ");
  return scheme?.toLowerCase() === "bearer" ? token : "";
}

async function requireUser(
  request: express.Request,
  response: express.Response
): Promise<AppUser | null> {
  const token = bearerToken(request);
  const user = token ? await authStore.getUserForSession(token) : null;
  if (!user) {
    response.status(401).json({ error: "Sign in again." });
  }
  return user;
}

app.get("/health", (_request, response) => {
  response.json({ ok: true });
});

app.post("/api/auth/google", async (request, response) => {
  try {
    if (!config.googleWebClientId) {
      response.status(500).json({ error: "Missing GOOGLE_WEB_CLIENT_ID." });
      return;
    }

    const idToken = String(request.body?.idToken ?? "");
    if (!idToken) {
      response.status(400).json({ error: "Missing Google ID token." });
      return;
    }

    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: config.googleWebClientId
    });
    const payload = ticket.getPayload();
    if (!payload?.sub || !payload.email) {
      response.status(401).json({ error: "Invalid Google identity." });
      return;
    }

    const user = await authStore.upsertUser({
      provider: "google",
      providerSubject: payload.sub,
      email: payload.email,
      displayName: payload.name ?? payload.email,
      photoUrl: payload.picture
    });
    const session = await authStore.createSession(
      user.id,
      config.authSessionDays
    );

    response.json({ user, session });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/apple", async (request, response) => {
  try {
    const identityToken = String(request.body?.identityToken ?? "");
    if (!identityToken) {
      response.status(400).json({ error: "Missing Apple identity token." });
      return;
    }

    const { payload } = await jwtVerify(identityToken, appleKeys, {
      issuer: "https://appleid.apple.com",
      audience: config.appleBundleId
    });
    if (!payload.sub) {
      response.status(401).json({ error: "Invalid Apple identity." });
      return;
    }

    const email =
      typeof payload.email === "string"
        ? payload.email
        : String(request.body?.email ?? "");
    const displayName = String(request.body?.displayName ?? "").trim();
    const existing = await authStore.findUser("apple", payload.sub);
    const user = await authStore.upsertUser({
      provider: "apple",
      providerSubject: payload.sub,
      email: email || existing?.email || "",
      displayName:
        displayName ||
        (existing?.displayName.includes("@") ? "" : existing?.displayName) ||
        ""
    });
    const session = await authStore.createSession(
      user.id,
      config.authSessionDays
    );

    response.json({ user, session });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/local", async (request, response) => {
  try {
    if (!config.allowLocalAuth) {
      response.status(403).json({ error: "Local auth is disabled." });
      return;
    }

    const email = String(request.body?.email ?? "").trim().toLowerCase();
    const displayName = String(request.body?.displayName ?? "").trim();
    if (!email || !email.includes("@")) {
      response.status(400).json({ error: "A valid email is required." });
      return;
    }

    const user = await authStore.upsertUser({
      provider: "local",
      providerSubject: email,
      email,
      displayName: displayName || email,
      photoUrl: ""
    });
    const session = await authStore.createSession(
      user.id,
      config.authSessionDays
    );

    response.json({ user, session });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/signup", async (request, response) => {
  try {
    const email = readEmail(request);
    const password = readPassword(request);
    if (!email) {
      response.status(400).json({ error: "Enter a valid email." });
      return;
    }
    if (password.length < 8 || password.length > 200) {
      response.status(400).json({ error: passwordRule });
      return;
    }
    if (tooManyAttempts(`signup:${request.ip}`, 10, 60)) {
      response.status(429).json({ error: "Too many attempts. Try again later." });
      return;
    }
    if (await passwordStore.exists(email)) {
      response.status(409).json({ error: "That email already has an account. Sign in instead." });
      return;
    }
    await passwordStore.set(email, password);
    const displayName = String(request.body?.displayName ?? "").trim().slice(0, 80);
    const user = await authStore.upsertUser({
      provider: "password",
      providerSubject: email,
      email,
      displayName: displayName || email
    });
    const session = await authStore.createSession(user.id, config.authSessionDays);
    response.json({ user, session });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/login", async (request, response) => {
  try {
    const email = readEmail(request);
    const password = readPassword(request);
    if (!email || !password) {
      response.status(400).json({ error: "Enter your email and password." });
      return;
    }
    if (tooManyAttempts(`login:${email}`, 10, 15)) {
      response.status(429).json({ error: "Too many attempts. Try again in 15 minutes." });
      return;
    }
    const user = await authStore.findUser("password", email);
    if (!(await passwordStore.verify(email, password)) || !user) {
      response.status(401).json({ error: "That email and password don't match." });
      return;
    }
    attempts.delete(`login:${email}`);
    const session = await authStore.createSession(user.id, config.authSessionDays);
    response.json({ user, session });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/password/forgot", async (request, response) => {
  try {
    const email = readEmail(request);
    if (!email) {
      response.status(400).json({ error: "Enter a valid email." });
      return;
    }
    if (!mailer.configured) {
      response.status(503).json({ error: "Password reset is not available yet." });
      return;
    }
    if (!tooManyAttempts(`forgot:${email}`, 3, 60)) {
      const code = await passwordStore.startReset(email);
      if (code) {
        await mailer.sendResetCode(email, code);
      }
    }
    response.status(204).send();
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/password/reset", async (request, response) => {
  try {
    const email = readEmail(request);
    const code = String(request.body?.code ?? "");
    const password = readPassword(request);
    if (password.length < 8 || password.length > 200) {
      response.status(400).json({ error: passwordRule });
      return;
    }
    const user = email ? await authStore.findUser("password", email) : null;
    if (!user || !(await passwordStore.finishReset(email, code, password))) {
      response.status(400).json({ error: "That code is wrong or has expired." });
      return;
    }
    await authStore.clearUserSessions(user.id);
    const session = await authStore.createSession(user.id, config.authSessionDays);
    response.json({ user, session });
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/auth/me", async (request, response) => {
  try {
    const token = bearerToken(request);
    if (!token) {
      response.status(401).json({ error: "Missing auth token." });
      return;
    }
    const user = await authStore.getUserForSession(token);
    if (!user) {
      response.status(401).json({ error: "Invalid or expired session." });
      return;
    }
    response.json({ user });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/auth/logout", async (request, response) => {
  try {
    const token = bearerToken(request);
    if (token) {
      await authStore.clearSession(token);
    }
    response.status(204).send();
  } catch (error) {
    handleError(error, response);
  }
});

app.patch("/api/account", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    const displayName = String(request.body?.displayName ?? "").trim().slice(0, 80);
    if (!displayName) {
      response.status(400).json({ error: "Enter your name." });
      return;
    }
    response.json({ user: await authStore.updateDisplayName(user.id, displayName) });
  } catch (error) {
    handleError(error, response);
  }
});

app.delete("/api/account", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    try {
      await whoop.revoke(user.id);
    } catch {
      // Deleting the account must not depend on WHOOP being reachable.
    }
    await mealStore.removeAll(user.id);
    await usageStore.removeAll(user.id);
    try {
      await billing.cancelFor(user.id);
    } catch (error) {
      console.error("stripe cancel failed during account deletion", user.id, error);
    }
    if (user.provider === "password") {
      await passwordStore.remove(user.providerSubject);
    }
    await authStore.deleteUser(user.id);
    response.status(204).send();
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/log", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    if (!(await requireSubscription(user, response))) {
      return;
    }
    const text = String(request.body?.text ?? "").trim();
    const images = readImages(request.body?.images);
    if (images === null) {
      response.status(400).json({ error: "Attach up to 3 JPEG or PNG photos." });
      return;
    }
    if (!text && images.length === 0) {
      response.status(400).json({ error: "Tell me what you ate or did." });
      return;
    }
    if (text.length > 8000) {
      response.status(400).json({ error: "That log is too long." });
      return;
    }
    const bodyWeight = Number(request.body?.bodyWeightLb);
    response.json(
      await logParser.parse(
        text,
        await mealStore.list(user.id),
        Number.isFinite(bodyWeight) && bodyWeight > 50 && bodyWeight < 700
          ? Math.round(bodyWeight)
          : null,
        images,
        user.id
      )
    );
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/subscription", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    response.json(await subscriptions.status(user.id));
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/billing/checkout", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    response.json({ url: await billing.checkoutUrl(user.id, user.email) });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/billing/portal", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    response.json({ url: await billing.portalUrl(user.id) });
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/billing/done", (request, response) => {
  const status = String(request.query.status ?? "");
  const message =
    status === "success"
      ? "You're subscribed. Thank you!"
      : status === "cancelled"
        ? "No charge was made."
        : "All set.";
  response.type("html").send(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Sculptus</title></head>
<body style="font-family:-apple-system,system-ui,sans-serif;text-align:center;padding:72px 24px;background:#f7f6f4;color:#1c1917">
<h1 style="font-size:24px">${message}</h1>
<p style="color:#78716c">Head back to Sculptus to keep logging.</p>
<a href="sculptus://billing" style="display:inline-block;margin-top:16px;padding:14px 28px;border-radius:14px;background:#7A2738;color:#fff;text-decoration:none;font-weight:600">Open Sculptus</a>
</body></html>`);
});

app.post("/api/meals/estimate", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    if (!(await requireSubscription(user, response))) {
      return;
    }
    const name = String(request.body?.name ?? "").trim().slice(0, 80);
    const ingredients = String(request.body?.ingredients ?? "").trim();
    if (!ingredients || ingredients.length > 4000) {
      response.status(400).json({ error: "List what's in the meal." });
      return;
    }
    const portions = Math.min(Math.max(Math.round(Number(request.body?.portions) || 1), 1), 50);
    response.json(await logParser.estimateMeal(name, ingredients, portions, user.id));
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/meals", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    response.json({ meals: await mealStore.list(user.id) });
  } catch (error) {
    handleError(error, response);
  }
});

app.put("/api/meals", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    const name = String(request.body?.name ?? "").trim().slice(0, 80);
    const calories = Math.round(Number(request.body?.calories));
    const proteinGrams = Number(request.body?.proteinGrams ?? 0);
    if (!name || !Number.isFinite(calories) || calories < 0 || calories > 5000) {
      response.status(400).json({ error: "A meal needs a name and calories." });
      return;
    }
    if ((await mealStore.list(user.id)).length >= 100) {
      response.status(400).json({ error: "You can save up to 100 meals." });
      return;
    }
    const portions = Math.min(Math.max(Math.round(Number(request.body?.portions) || 1), 1), 50);
    await mealStore.save(user.id, {
      name,
      calories,
      proteinGrams: Number.isFinite(proteinGrams) ? Math.max(0, proteinGrams) : 0,
      ingredients: String(request.body?.ingredients ?? "").trim().slice(0, 4000),
      portions
    });
    response.json({ meals: await mealStore.list(user.id) });
  } catch (error) {
    handleError(error, response);
  }
});

app.delete("/api/meals/:name", async (request, response) => {
  try {
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    await mealStore.remove(user.id, request.params.name);
    response.json({ meals: await mealStore.list(user.id) });
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/whoop/connect", async (request, response) => {
  try {
    assertWhoopConfig();
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    const state = newOauthState();
    oauthStates.set(state, {
      userId: user.id,
      expiresAt: Date.now() + 10 * 60 * 1000
    });
    response.json({
      authorizationUrl: whoop.buildAuthorizationUrl(state),
      scopes: config.whoopScopes
    });
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/whoop/callback", async (request, response) => {
  try {
    assertWhoopConfig();
    const code = String(request.query.code ?? "");
    const state = String(request.query.state ?? "");
    const pending = oauthStates.get(state);

    if (!code) {
      response.status(400).send("Missing WHOOP authorization code.");
      return;
    }
    if (!pending || pending.expiresAt < Date.now()) {
      response.status(400).send("Invalid or expired WHOOP OAuth state.");
      return;
    }

    oauthStates.delete(state);
    await whoop.exchangeCode(pending.userId, code);
    response
      .status(200)
      .send("WHOOP connected. You can return to Sculptus and sync the day.");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    response.status(500).send(message);
  }
});

app.get("/api/whoop/summary", async (request, response) => {
  try {
    assertWhoopConfig();
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    const date =
      typeof request.query.date === "string"
        ? request.query.date
        : new Date().toISOString().slice(0, 10);
    const summary = await whoop.dailySummary(user.id, date);
    response.json(summary);
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/whoop/steps", async (request, response) => {
  try {
    assertWhoopConfig();
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    const date =
      typeof request.query.date === "string"
        ? request.query.date
        : new Date().toISOString().slice(0, 10);
    const summary = await whoop.dailySummary(user.id, date);
    response.json({
      date,
      steps: summary.steps,
      stepsSource: summary.stepsSource,
      stepsRecordedAt: summary.stepsRecordedAt
    });
  } catch (error) {
    handleError(error, response);
  }
});

app.post("/api/whoop/disconnect", async (request, response) => {
  try {
    assertWhoopConfig();
    const user = await requireUser(request, response);
    if (!user) {
      return;
    }
    await whoop.revoke(user.id);
    response.status(204).send();
  } catch (error) {
    handleError(error, response);
  }
});

app.listen(config.port, () => {
  console.log(`Sculptus backend listening on http://127.0.0.1:${config.port}`);
});
