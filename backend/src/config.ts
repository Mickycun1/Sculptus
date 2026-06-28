import "dotenv/config";

export const config = {
  port: Number(process.env.PORT ?? 8787),
  mongoUri: process.env.MONGODB_URI ?? "",
  mongoDbName: process.env.MONGODB_DB ?? "sculptus",
  userKey: process.env.SCULPTUS_USER_KEY ?? "local-user",
  googleWebClientId: process.env.GOOGLE_WEB_CLIENT_ID ?? "",
  authSessionDays: Number(process.env.AUTH_SESSION_DAYS ?? 30),
  allowLocalAuth: process.env.SCULPTUS_ALLOW_LOCAL_AUTH !== "false",
  whoopClientId: process.env.WHOOP_CLIENT_ID ?? "",
  whoopClientSecret: process.env.WHOOP_CLIENT_SECRET ?? "",
  whoopRedirectUri:
    process.env.WHOOP_REDIRECT_URI ??
    "http://127.0.0.1:8787/api/whoop/callback",
  whoopScopes: [
    "offline",
    "read:profile",
    "read:body_measurement",
    "read:recovery",
    "read:cycles",
    "read:sleep",
    "read:workout"
  ]
};

export function assertWhoopConfig() {
  const missing = [
    ["WHOOP_CLIENT_ID", config.whoopClientId],
    ["WHOOP_CLIENT_SECRET", config.whoopClientSecret],
    ["WHOOP_REDIRECT_URI", config.whoopRedirectUri]
  ].filter(([, value]) => !value);

  if (missing.length > 0) {
    throw new Error(
      `Missing WHOOP config: ${missing.map(([key]) => key).join(", ")}`
    );
  }
}
