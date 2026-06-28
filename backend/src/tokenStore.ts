import { Collection, MongoClient } from "mongodb";

export type WhoopTokens = {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  scope: string;
  tokenType: string;
};

export interface TokenStore {
  get(userKey: string): Promise<WhoopTokens | null>;
  set(userKey: string, tokens: WhoopTokens): Promise<void>;
  clear(userKey: string): Promise<void>;
}

export class MemoryTokenStore implements TokenStore {
  private readonly tokens = new Map<string, WhoopTokens>();

  async get(userKey: string) {
    return this.tokens.get(userKey) ?? null;
  }

  async set(userKey: string, tokens: WhoopTokens) {
    this.tokens.set(userKey, tokens);
  }

  async clear(userKey: string) {
    this.tokens.delete(userKey);
  }
}

class MongoTokenStore implements TokenStore {
  constructor(private readonly collection: Collection) {}

  async get(userKey: string) {
    const doc = await this.collection.findOne({ userKey });
    if (!doc) {
      return null;
    }
    return {
      accessToken: doc.accessToken as string,
      refreshToken: doc.refreshToken as string,
      expiresAt: doc.expiresAt as number,
      scope: doc.scope as string,
      tokenType: doc.tokenType as string
    };
  }

  async set(userKey: string, tokens: WhoopTokens) {
    await this.collection.updateOne(
      { userKey },
      { $set: { userKey, ...tokens, updatedAt: new Date() } },
      { upsert: true }
    );
  }

  async clear(userKey: string) {
    await this.collection.deleteOne({ userKey });
  }
}

export async function createTokenStore(
  mongoUri: string,
  dbName: string
): Promise<TokenStore> {
  if (!mongoUri) {
    return new MemoryTokenStore();
  }

  const client = new MongoClient(mongoUri);
  await client.connect();
  const collection = client.db(dbName).collection("whoop_tokens");
  await collection.createIndex({ userKey: 1 }, { unique: true });
  return new MongoTokenStore(collection);
}
