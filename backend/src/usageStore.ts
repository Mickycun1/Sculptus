import { Collection, MongoClient } from "mongodb";

export type UsageRecord = {
  userId: string;
  route: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  costUsd: number;
  at: Date;
};

const PRICES: Record<string, { input: number; output: number }> = {
  "claude-opus-5-5": { input: 4, output: 20 },
  "claude-opus-5": { input: 5, output: 25 },
  "claude-opus-4-8": { input: 5, output: 25 },
  "claude-sonnet-5-5": { input: 2, output: 10 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5 }
};

export function costOf(
  model: string,
  usage: Omit<UsageRecord, "userId" | "route" | "model" | "costUsd" | "at">
) {
  const price =
    Object.entries(PRICES).find(([name]) => model.startsWith(name))?.[1] ??
    PRICES["claude-opus-5-5"];
  return (
    (usage.inputTokens * price.input +
      usage.cacheWriteTokens * price.input * 1.25 +
      usage.cacheReadTokens * price.input * 0.05 +
      usage.outputTokens * price.output) /
    1_000_000
  );
}

export interface UsageStore {
  record(entry: UsageRecord): Promise<void>;
  removeAll(userId: string): Promise<void>;
}

class MemoryUsageStore implements UsageStore {
  readonly entries: UsageRecord[] = [];

  async record(entry: UsageRecord) {
    this.entries.push(entry);
  }

  async removeAll(userId: string) {
    for (let i = this.entries.length - 1; i >= 0; i--) {
      if (this.entries[i].userId === userId) {
        this.entries.splice(i, 1);
      }
    }
  }
}

class MongoUsageStore implements UsageStore {
  constructor(private readonly collection: Collection<UsageRecord>) {}

  async record(entry: UsageRecord) {
    await this.collection.insertOne(entry);
  }

  async removeAll(userId: string) {
    await this.collection.deleteMany({ userId });
  }
}

export async function createUsageStore(
  mongoUri: string,
  dbName: string
): Promise<UsageStore> {
  if (!mongoUri) {
    return new MemoryUsageStore();
  }
  const client = new MongoClient(mongoUri);
  await client.connect();
  const collection = client.db(dbName).collection<UsageRecord>("usage");
  await collection.createIndex({ userId: 1, at: -1 });
  return new MongoUsageStore(collection);
}
