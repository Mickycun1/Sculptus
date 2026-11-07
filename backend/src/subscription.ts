import type { Billing } from "./billing.js";

export type SubscriptionStatus = {
  active: boolean;
  exempt: boolean;
  enforced: boolean;
};

export class SubscriptionChecker {
  constructor(
    private readonly billing: Billing,
    private readonly exemptUserIds: Set<string>
  ) {}

  async status(userId: string): Promise<SubscriptionStatus> {
    const exempt = this.exemptUserIds.has(userId);
    const enforced = this.billing.enabled;
    if (exempt || !enforced) {
      return { active: true, exempt, enforced };
    }
    return { active: await this.billing.status(userId), exempt, enforced };
  }

  async isActive(userId: string) {
    return (await this.status(userId)).active;
  }
}
