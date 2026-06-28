import cors from "cors";
import express from "express";
import crypto from "node:crypto";
import { OAuth2Client } from "google-auth-library";
import { createAuthStore } from "./authStore.js";
import { assertWhoopConfig, config } from "./config.js";
import { createTokenStore } from "./tokenStore.js";
import { WhoopClient } from "./whoopClient.js";

const app = express();
app.use(cors());
app.use(express.json());

const oauthStates = new Map<string, number>();
const authStore = await createAuthStore(config.mongoUri, config.mongoDbName);
const tokenStore = await createTokenStore(config.mongoUri, config.mongoDbName);
const whoop = new WhoopClient(tokenStore);
const googleClient = new OAuth2Client(config.googleWebClientId || undefined);

function newOauthState() {
  return crypto.randomBytes(4).toString("hex");
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

app.get("/api/whoop/connect", (_request, response) => {
  try {
    assertWhoopConfig();
    const state = newOauthState();
    oauthStates.set(state, Date.now() + 10 * 60 * 1000);
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
    const expiresAt = oauthStates.get(state) ?? 0;

    if (!code) {
      response.status(400).send("Missing WHOOP authorization code.");
      return;
    }
    if (!state || expiresAt < Date.now()) {
      response.status(400).send("Invalid or expired WHOOP OAuth state.");
      return;
    }

    oauthStates.delete(state);
    await whoop.exchangeCode(config.userKey, code);
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
    const date =
      typeof request.query.date === "string"
        ? request.query.date
        : new Date().toISOString().slice(0, 10);
    const summary = await whoop.dailySummary(config.userKey, date);
    response.json(summary);
  } catch (error) {
    handleError(error, response);
  }
});

app.get("/api/whoop/steps", async (request, response) => {
  try {
    assertWhoopConfig();
    const date =
      typeof request.query.date === "string"
        ? request.query.date
        : new Date().toISOString().slice(0, 10);
    const summary = await whoop.dailySummary(config.userKey, date);
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

app.post("/api/whoop/disconnect", async (_request, response) => {
  try {
    assertWhoopConfig();
    await whoop.revoke(config.userKey);
    response.status(204).send();
  } catch (error) {
    handleError(error, response);
  }
});

app.listen(config.port, () => {
  console.log(`Sculptus backend listening on http://127.0.0.1:${config.port}`);
});
