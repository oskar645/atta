import { Injectable } from '@nestjs/common';

// Invalidation only: never a counter or a source of truth.
@Injectable()
export class AnalyticsSignal {
  private listeners = new Set<() => void>();
  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }
  changed() {
    for (const listener of this.listeners) {
      try { listener(); } catch { /* Analytics must not fail chat writes. */ }
    }
  }
}
