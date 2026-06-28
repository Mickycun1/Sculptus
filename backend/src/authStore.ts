import crypto from "node:crypto";
import { Collection, MongoClient } from "mongodb";

export type AppUser = {
  id: string;
  provider: "google" | "local";
  providerSubject: string;
  email: string;
  displayName: string;
  photoUrl: string;
  createdAt: string;
  updatedAt: string;
};

export type AppSession = {
  token: string;
  userId: string;
  expiresAt: string;
  createdAt: string;
};

export type AuthProfile = {
  provider: "google" | "local";
  providerSubject: string;
  email: string;
  displayName: string;
  photoUrl?: string;
};

export interface AuthStore {
  upsertUser(profile: AuthProfile): Promise<AppUser>;
  createSession(userId: string, sessionDays: number): Promise<AppSession>;
  getUserForSession(token: string): Promise<AppUser | null>;
  clearSession(token: string): Promise<void>;
}

function nowIso() {
  return new Date().toISOString();
}

function newToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function newUserId() {
  return `user_${crypto.randomUUID()}`;
}

function sessionExpiry(sessionDays: number) {
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + sessionDays);
  return expiresAt.toISOString();
}

export class MemoryAuthStore implements AuthStore {
  private readonly users = new Map<string, AppUser>();
  private readonly sessions = new Map<string, AppSession>();

  async upsertUser(profile: AuthProfile) {
    const key = `${profile.provider}:${profile.providerSubject}`;
    const existing = this.users.get(key);
    const updatedAt = nowIso();
    const user: AppUser = {
      id: existing?.id ?? newUserId(),
      provider: profile.provider,
      providerSubject: profile.providerSubject,
      email: profile.email,
      displayName: profile.displayName,
      photoUrl: profile.photoUrl ?? "",
      createdAt: existing?.createdAt ?? updatedAt,
      updatedAt
    };
    this.users.set(key, user);
    return user;
  }

  async createSession(userId: string, sessionDays: number) {
    const session: AppSession = {
      token: newToken(),
      userId,
      createdAt: nowIso(),
      expiresAt: sessionExpiry(sessionDays)
    };
    this.sessions.set(session.token, session);
    return session;
  }

  async getUserForSession(token: string) {
    const session = this.sessions.get(token);
    if (!session || Date.parse(session.expiresAt) < Date.now()) {
      return null;
    }
    return [...this.users.values()].find((user) => user.id === session.userId) ?? null;
  }

  async clearSession(token: string) {
    this.sessions.delete(token);
  }
}

class MongoAuthStore implements AuthStore {
  constructor(
    private readonly users: Collection<AppUser>,
    private readonly sessions: Collection<AppSession>
  ) {}

  async upsertUser(profile: AuthProfile) {
    const updatedAt = nowIso();
    const existing = await this.users.findOne({
      provider: profile.provider,
      providerSubject: profile.providerSubject
    });
    const user: AppUser = {
      id: existing?.id ?? newUserId(),
      provider: profile.provider,
      providerSubject: profile.providerSubject,
      email: profile.email,
      displayName: profile.displayName,
      photoUrl: profile.photoUrl ?? "",
      createdAt: existing?.createdAt ?? updatedAt,
      updatedAt
    };
    await this.users.updateOne(
      { provider: user.provider, providerSubject: user.providerSubject },
      { $set: user },
      { upsert: true }
    );
    return user;
  }

  async createSession(userId: string, sessionDays: number) {
    const session: AppSession = {
      token: newToken(),
      userId,
      createdAt: nowIso(),
      expiresAt: sessionExpiry(sessionDays)
    };
    await this.sessions.insertOne(session);
    return session;
  }

  async getUserForSession(token: string) {
    const session = await this.sessions.findOne({ token });
    if (!session || Date.parse(session.expiresAt) < Date.now()) {
      return null;
    }
    return this.users.findOne({ id: session.userId });
  }

  async clearSession(token: string) {
    await this.sessions.deleteOne({ token });
  }
}

export async function createAuthStore(
  mongoUri: string,
  dbName: string
): Promise<AuthStore> {
  if (!mongoUri) {
    return new MemoryAuthStore();
  }

  const client = new MongoClient(mongoUri);
  await client.connect();
  const db = client.db(dbName);
  const users = db.collection<AppUser>("users");
  const sessions = db.collection<AppSession>("sessions");
  await users.createIndex(
    { provider: 1, providerSubject: 1 },
    { unique: true }
  );
  await sessions.createIndex({ token: 1 }, { unique: true });
  await sessions.createIndex({ expiresAt: 1 });
  return new MongoAuthStore(users, sessions);
}
