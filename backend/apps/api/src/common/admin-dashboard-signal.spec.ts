import assert from 'node:assert/strict';
import { test } from 'node:test';

import { AdminDashboardSignal } from './admin-dashboard-signal';

test('coalesces high-frequency changes into one scoped notification', () => {
  const signal = new AdminDashboardSignal();
  const calls: string[][] = [];
  signal.subscribe((scopes) => calls.push(scopes));

  signal.changed('presence');
  signal.changed('presence', 'searches');
  signal.changed('searches', 'listings');
  signal.flush();

  assert.equal(calls.length, 1);
  assert.deepEqual(
    new Set(calls[0]),
    new Set(['presence', 'searches', 'listings']),
  );
  signal.onModuleDestroy();
});

test('isolates completed business writes from listener failures', () => {
  const signal = new AdminDashboardSignal();
  const calls: string[][] = [];
  signal.subscribe(() => {
    throw new Error('socket unavailable');
  });
  signal.subscribe((scopes) => calls.push(scopes));

  signal.changed('payments');
  assert.doesNotThrow(() => signal.flush());
  assert.deepEqual(calls, [['payments']]);
  signal.onModuleDestroy();
});
