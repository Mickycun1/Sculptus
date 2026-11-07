import Stripe from "stripe";
import { Collection, MongoClient } from "mongodb";

export type BillingRecord = {
  userId: string;
  customerId: string;
  subscriptionId: string;
  status: string;
  currentPeriodEnd: number;
  updatedAt: Date;
};

const ACTIVE_STATUSES = new Set(["active", "trialing", "past_due"]);

export function isActive(record: BillingRecord | null) {
  return Boolean(
    record &&
      ACTIVE_STATUSES.has(record.status) &&
      record.currentPeriodEnd * 1000 > Date.now()
  );
}

export interface BillingStore {
  forUser(userId: string): Promise<BillingRecord | null>;
  forCustomer(customerId: string): Promise<BillingRecord | null>;
  save(record: BillingRecord): Promise<void>;
  remove(userId: string): Promise<void>;
}

class MemoryBillingStore implements BillingStore {
  private readonly records = new Map<string, BillingRecord>();

  async forUser(userId: string) {
    return this.records.get(userId) ?? null;
  }

  async forCustomer(customerId: string) {
    return [...this.records.values()].find((r) => r.customerId === customerId) ?? null;
  }

  async save(record: BillingRecord) {
    this.records.set(record.userId, record);
  }

  async remove(userId: string) {
    this.records.delete(userId);
  }
}

class MongoBillingStore implements BillingStore {
  constructor(private readonly collection: Collection<BillingRecord>) {}

  async forUser(userId: string) {
    return this.collection.findOne({ userId }, { projection: { _id: 0 } });
  }

  async forCustomer(customerId: string) {
    return this.collection.findOne({ customerId }, { projection: { _id: 0 } });
  }

  async save(record: BillingRecord) {
    await this.collection.replaceOne({ userId: record.userId }, record, {
      upsert: true
    });
  }

  async remove(userId: string) {
    await this.collection.deleteOne({ userId });
  }
}

export async function createBillingStore(mongoUri: string, dbName: string) {
  if (!mongoUri) {
    return new MemoryBillingStore();
  }
  const client = new MongoClient(mongoUri);
  await client.connect();
  const collection = client.db(dbName).collection<BillingRecord>("billing");
  await collection.createIndex({ userId: 1 }, { unique: true });
  await collection.createIndex({ customerId: 1 });
  return new MongoBillingStore(collection);
}

export class Billing {
  private readonly stripe: Stripe | null;

  constructor(
    secretKey: string,
    private readonly priceId: string,
    private readonly webhookSecret: string,
    private readonly publicUrl: string,
    private readonly store: BillingStore
  ) {
    this.stripe = secretKey ? new Stripe(secretKey) : null;
  }

  get enabled() {
    return Boolean(this.stripe && this.priceId);
  }

  private client() {
    if (!this.stripe) {
      throw new Error("Payments are not set up yet.");
    }
    return this.stripe;
  }

  async checkoutUrl(userId: string, email: string) {
    const existing = await this.store.forUser(userId);
    const session = await this.client().checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: this.priceId, quantity: 1 }],
      client_reference_id: userId,
      metadata: { userId },
      subscription_data: { metadata: { userId } },
      ...(existing?.customerId
        ? { customer: existing.customerId }
        : email && !email.endsWith("privaterelay.appleid.com")
          ? { customer_email: email }
          : {}),
      allow_promotion_codes: true,
      success_url: `${this.publicUrl}/billing/done?status=success`,
      cancel_url: `${this.publicUrl}/billing/done?status=cancelled`
    });
    if (!session.url) {
      throw new Error("Stripe did not return a checkout page.");
    }
    return session.url;
  }

  async portalUrl(userId: string) {
    const record = await this.store.forUser(userId);
    if (!record) {
      throw new Error("No subscription found for this account.");
    }
    const session = await this.client().billingPortal.sessions.create({
      customer: record.customerId,
      return_url: `${this.publicUrl}/billing/done?status=portal`
    });
    return session.url;
  }

  async status(userId: string) {
    return isActive(await this.store.forUser(userId));
  }

  async cancelFor(userId: string) {
    const record = await this.store.forUser(userId);
    if (record && this.stripe && isActive(record)) {
      await this.stripe.subscriptions.cancel(record.subscriptionId);
    }
    await this.store.remove(userId);
  }

  async handleWebhook(rawBody: Buffer, signature: string) {
    const event = this.client().webhooks.constructEvent(
      rawBody,
      signature,
      this.webhookSecret
    );
    if (
      event.type === "customer.subscription.created" ||
      event.type === "customer.subscription.updated" ||
      event.type === "customer.subscription.deleted"
    ) {
      await this.saveSubscription(event.data.object);
    } else if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      if (typeof session.subscription === "string") {
        await this.saveSubscription(
          await this.client().subscriptions.retrieve(session.subscription)
        );
      }
    }
  }

  private async saveSubscription(subscription: Stripe.Subscription) {
    const customerId =
      typeof subscription.customer === "string"
        ? subscription.customer
        : subscription.customer.id;
    const userId =
      subscription.metadata?.userId ||
      (await this.store.forCustomer(customerId))?.userId;
    if (!userId) {
      console.error("stripe subscription without a user", subscription.id);
      return;
    }
    const periodEnd = Math.max(
      0,
      ...subscription.items.data.map((item) => item.current_period_end ?? 0)
    );
    await this.store.save({
      userId,
      customerId,
      subscriptionId: subscription.id,
      status: subscription.status,
      currentPeriodEnd: periodEnd,
      updatedAt: new Date()
    });
  }
}
