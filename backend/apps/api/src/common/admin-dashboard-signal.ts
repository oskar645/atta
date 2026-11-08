import { Injectable, OnModuleDestroy } from '@nestjs/common';

export const ADMIN_DASHBOARD_SCOPES = [
  'users',
  'presence',
  'visits',
  'usage',
  'listings',
  'wallet',
  'payments',
  'promotions',
  'support',
  'reports',
  'ads',
  'searches',
] as const;

export type AdminDashboardScope = (typeof ADMIN_DASHBOARD_SCOPES)[number];

@Injectable()
export class AdminDashboardSignal implements OnModuleDestroy {
  private readonly listeners = new Set<(scopes: AdminDashboardScope[]) => void>();
  private readonly pending = new Set<AdminDashboardScope>();
  private timer?: ReturnType<typeof setTimeout>;

  subscribe(listener: (scopes: AdminDashboardScope[]) => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  changed(...scopes: AdminDashboardScope[]) {
    for (const scope of scopes) this.pending.add(scope);
    if (this.timer || this.pending.size === 0) return;
    this.timer = setTimeout(() => this.flush(), 500);
  }

  flush() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    if (this.pending.size === 0) return;
    const scopes = [...this.pending];
    this.pending.clear();
    for (const listener of this.listeners) {
      try {
        listener(scopes);
      } catch {
        // Dashboard invalidation must never affect the completed business write.
      }
    }
  }

  onModuleDestroy() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this.pending.clear();
    this.listeners.clear();
  }
}
