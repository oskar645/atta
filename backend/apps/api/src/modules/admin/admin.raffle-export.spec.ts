import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { AdminController } from './admin.controller';

class FakeResponse extends EventEmitter {
  statusCode = 200;
  headers: Record<string, string> = {};
  output = '';
  setHeader(name: string, value: string) { this.headers[name] = value; }
  status(code: number) { this.statusCode = code; return this; }
  json(value: unknown) { this.output = JSON.stringify(value); return this; }
  write(chunk: string) { this.output += chunk; return true; }
  end() { this.emit('finish'); }
}

test('print export repeats each user exactly once per ticket with unique numbers', async () => {
  const response = new FakeResponse();
  const receivedPrices: string[] = [];
  const controller = new AdminController({
    getRaffleSummary: async () => ({
      from: '2026-10-01', to: '2026-10-31', participants: 2,
      tickets: 5, amountRub: 7000, ticketPriceRub: '1000',
    }),
    listRaffleParticipants: async (query: { ticketPrice: string; cursor?: string }) => {
      receivedPrices.push(query.ticketPrice);
      return query.cursor
        ? { items: [{ name: 'Адам', phone: '+79992222222', tickets: 3 }], nextCursor: null }
        : { items: [{ name: 'Иван', phone: '+79991111111', tickets: 2 }], nextCursor: 'next-page' };
    },
  } as any, {} as any);
  await controller.exportRaffle({ from: '2026-10-01', to: '2026-10-31', ticketPrice: '1000' },
    'tickets', response as any);
  const lines = response.output.trim().split('\r\n');
  const ticketLines = lines.filter((line) => /^"[1-5]";/.test(line));
  assert.deepEqual(ticketLines, [
    '"1";"Иван";"\'+79991111111"',
    '"2";"Иван";"\'+79991111111"',
    '"3";"Адам";"\'+79992222222"',
    '"4";"Адам";"\'+79992222222"',
    '"5";"Адам";"\'+79992222222"',
  ]);
  assert.deepEqual(receivedPrices, ['1000', '1000']);
  assert.ok(lines.includes('"Цена билета, ₽";"1000"'));
  assert.equal(ticketLines.length, 5);
  assert.match(response.headers['Content-Disposition'], /raffle-tickets.csv/);
});
