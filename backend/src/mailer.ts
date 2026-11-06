export class Mailer {
  constructor(
    private readonly apiKey: string,
    private readonly from: string
  ) {}

  get configured() {
    return Boolean(this.apiKey);
  }

  async sendResetCode(to: string, code: string) {
    if (!this.apiKey) {
      throw new Error("Email is not configured.");
    }
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        from: this.from,
        to: [to],
        subject: `Your Sculptus code: ${code}`,
        text:
          `Your Sculptus password reset code is ${code}.\n\n` +
          "It expires in 15 minutes. If you did not ask to reset your " +
          "password, you can ignore this email."
      })
    });
    if (!response.ok) {
      throw new Error(`Email send failed with HTTP ${response.status}.`);
    }
  }
}
