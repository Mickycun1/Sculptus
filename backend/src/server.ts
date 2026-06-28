import cors from "cors";
import express from "express";
import crypto from "node:crypto";
import { assertWhoopConfig, config } from "./config.js";
import { createTokenStore } from "./tokenStore.js";
import { WhoopClient } from "./whoopClient.js";

const app = express();
app.use(cors());
app.use(express.json());

const oauthStates = new Map<string, number>();
const tokenStore = await createTokenStore(config.mongoUri, config.mongoDbName);
const whoop = new WhoopClient(tokenStore);

function newOauthState() {
  return crypto.randomBytes(4).toString("hex");
}

function handleError(error: unknown, response: express.Response) {
  const message = error instanceof Error ? error.message : "Unexpected error";
  const status = message.includes("not connected") ? 409 : 500;
  response.status(status).json({ error: message });
}

app.get("/health", (_request, response) => {
  response.json({ ok: true });
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
