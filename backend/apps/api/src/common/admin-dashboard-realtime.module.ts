import { Global, Module } from '@nestjs/common';

import { AdminDashboardSignal } from './admin-dashboard-signal';
import { SupportRealtimeSignal } from './support-realtime-signal';

@Global()
@Module({
  providers: [AdminDashboardSignal, SupportRealtimeSignal],
  exports: [AdminDashboardSignal, SupportRealtimeSignal],
})
export class AdminDashboardRealtimeModule {}
