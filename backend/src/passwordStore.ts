import crypto from "node:crypto";
import { promisify } from "node:util";
import { Collection, MongoClient } from "mongodb";

const scrypt = promisify(crypto.scrypt) as (
  password: string,
  salt: Buffer,
  keyLength: number
) => Promise<Buffer>;

const KEY_LENGTH = 64;
const RESET_MINUTES = 15;
const RESET_ATTEMPTS = 5;

type Credential = {
  email: string;
  salt: string;
  hash: string;
  resetCodeHash?: string;
  resetExpiresAt?: number;
  resetAttempts?: number;
  updatedAt: Date;
};

export async function hashPassword(password: string) {
  const salt = crypto.randomBytes(16);
  const hash = await scrypt(password, salt, KEY_LENGTH);
  return { salt: salt.toString("base64"), hash: hash.toString("base64") };
}

async function matches(password: string, salt: string, hash: string) {
  const expected = Buffer.from(hash, "base64");
  const actual = await scrypt(password, Buffer.from(salt, "base64"), expected.length);
  return crypto.timingSafeEqual(actual, expected);
}

function hashCode(code: string) {
  return crypto.createHash("sha256").update(code).digest("base64");
}

export class PasswordStore {
  constructor(private readonly collection: CredentialCollection) {}

  async exists(email: string) {
    return Boolean(await this.collection.find(email));
  }

  async set(email: string, password: string) {
    const { salt, hash } = await hashPassword(password);
    await this.collection.save({ email, salt, hash, updatedAt: new Date() });
  }

  async verify(email: string, password: string) {
    const credential = await this.collection.find(email);
    if (!credential) {
      await hashPassword(password);
      return false;
    }
    return matches(password, credential.salt, credential.hash);
  }

  async startReset(email: string) {
    const credential = await this.collection.find(email);
    if (!credential) {
      return null;
    }
    const code = crypto.randomInt(0, 1_000_000).toString().padStart(6, "0");
    await this.collection.save({
      ...credential,
      resetCodeHash: hashCode(code),
      resetExpiresAt: Date.now() + RESET_MINUTES * 60 * 1000,
      resetAttempts: 0,
      updatedAt: new Date()
    });
    return code;
  }

  async finishReset(email: string, code: string, password: string) {
    const credential = await this.collection.find(email);
    if (
      !credential?.resetCodeHash ||
      !credential.resetExpiresAt ||
      credential.resetExpiresAt < Date.now() ||
      (credential.resetAttempts ?? 0) >= RESET_ATTEMPTS
    ) {
      return false;
    }
    const expected = Buffer.from(credential.resetCodeHash, "base64");
    const actual = Buffer.from(hashCode(code.trim()), "base64");
    if (!crypto.timingSafeEqual(actual, expected)) {
      await this.collection.save({
        ...credential,
        resetAttempts: (credential.resetAttempts ?? 0) + 1,
        updatedAt: new Date()
      });
      return false;
    }
    const { salt, hash } = await hashPassword(password);
    await this.collection.save({ email, salt, hash, updatedAt: new Date() });
    return true;
  }

  async remove(email: string) {
    await this.collection.remove(email);
  }
}

interface CredentialCollection {
  find(email: string): Promise<Credential | null>;
  save(credential: Credential): Promise<void>;
  remove(email: string): Promise<void>;
}

class MemoryCredentials implements CredentialCollection {
  private readonly items = new Map<string, Credential>();

  async find(email: string) {
    return this.items.get(email) ?? null;
  }

  async save(credential: Credential) {
    this.items.set(credential.email, credential);
  }

  async remove(email: string) {
    this.items.delete(email);
  }
}

class MongoCredentials implements CredentialCollection {
  constructor(private readonly collection: Collection<Credential>) {}

  async find(email: string) {
    return this.collection.findOne({ email }, { projection: { _id: 0 } });
  }

  async save(credential: Credential) {
    await this.collection.replaceOne({ email: credential.email }, credential, {
      upsert: true
    });
  }

  async remove(email: string) {
    await this.collection.deleteOne({ email });
  }
}

export async function createPasswordStore(mongoUri: string, dbName: string) {
  if (!mongoUri) {
    return new PasswordStore(new MemoryCredentials());
  }
  const client = new MongoClient(mongoUri);
  await client.connect();
  const collection = client.db(dbName).collection<Credential>("credentials");
  await collection.createIndex({ email: 1 }, { unique: true });
  return new PasswordStore(new MongoCredentials(collection));
}
