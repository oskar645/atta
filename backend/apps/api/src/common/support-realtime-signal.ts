import { Injectable, OnModuleDestroy } from '@nestjs/common';

export type SupportRealtimeEvent = {
  ticketId: string;
  userId: string | null;
  messageId?: string;
  action: 'created' | 'updated' | 'deleted' | 'read';
};

@Injectable()
export class SupportRealtimeSignal implements OnModuleDestroy {
  private readonly listeners = new Set<(event: SupportRealtimeEvent) => void>();

  subscribe(listener: (event: SupportRealtimeEvent) => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  changed(event: SupportRealtimeEvent) {
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch {
        // Realtime invalidation must never affect a committed support write.
      }
    }
  }

  onModuleDestroy() {
    this.listeners.clear();
  }
}
