// Short-lived network limits. Issuance and per-space budgets are persisted separately in SQLite.
export class WindowLimiter {
  constructor({ now = Date.now, capacity = 10000 } = {}) {
    this.now = now; this.capacity = capacity; this.entries = new Map(); this.nextSweep = 0;
  }
  allow(key, limit, window, amount = 1) {
    const time = this.now();
    if (time >= this.nextSweep) {
      for (const [name, value] of this.entries) if (value.until <= time) this.entries.delete(name);
      // At capacity, check expiry at most once a second rather than scanning on every rejected request.
      this.nextSweep = time + (this.entries.size >= this.capacity ? 1000 : 30000);
    }
    let entry = this.entries.get(key);
    if (entry && entry.until <= time) { this.entries.delete(key); entry = undefined; }
    if (!entry && this.entries.size >= this.capacity) return false;
    if (amount > limit || (entry?.used ?? 0) + amount > limit) return false;
    if (!entry) { entry = { used: 0, until: time + window }; this.entries.set(key, entry); }
    entry.used += amount;
    // Reaching capacity must schedule cleanup too; the old implementation could never reach its sweep.
    if (this.entries.size >= this.capacity) this.nextSweep = Math.min(this.nextSweep, time + 1000);
    return true;
  }
}
