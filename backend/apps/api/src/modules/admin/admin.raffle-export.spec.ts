import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { AdminController } from './admin.controller';
import { ListRaffleParticipantsDto } from './dto/list-raffle-participants.dto';

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

class FakePdfResponse extends PassThrough {
  headers: Record<string, string> = {};
  setHeader(name: string, value: string) { this.headers[name] = value; }
}

test('export format is accepted by the strict global query contract', async () => {
  const query = plainToInstance(ListRaffleParticipantsDto, {
    from: '2026-10-01T00:00:00.000Z',
    to: '2026-10-31T23:59:59.999Z',
    ticketPrice: '1000',
    format: 'tickets',
  });
  const errors = await validate(query, {
    whitelist: true,
    forbidNonWhitelisted: true,
  });
  assert.deepEqual(errors, []);
});

test('print export repeats each user exactly once per ticket with unique numbers', async () => {
  const response = new FakeResponse();
  const receivedPrices: string[] = [];
  const controller = new AdminController({
    getRaffleSummary: async () => ({
      from: '2026-10-01', to: '2026-10-31', participants: 2,
      tickets: 5, amountRub: 7000, ticketPriceRub: '1000',
    }),
    listRaffleTickets: async (query: { ticketPrice?: string; cursor?: string }) => {
      receivedPrices.push(query.ticketPrice!);
      return query.cursor
        ? { items: [
          { ticketNumber: '3', name: 'Адам', phone: '+79992222222' },
          { ticketNumber: '4', name: 'Адам', phone: '+79992222222' },
          { ticketNumber: '5', name: 'Адам', phone: '+79992222222' },
        ], nextCursor: null }
        : { items: [
          { ticketNumber: '1', name: 'Иван', phone: '+79991111111' },
          { ticketNumber: '2', name: 'Иван', phone: '+79991111111' },
        ], nextCursor: '2' };
    },
  } as any, {} as any);
  await controller.exportRaffle({
    from: '2026-10-01', to: '2026-10-31', ticketPrice: '1000', format: 'tickets',
  }, response as any);
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

test('PDF print streams compact tickets with a real PDF header', async () => {
  const response = new FakePdfResponse();
  const chunks: Buffer[] = [];
  response.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
  const finished = new Promise<void>((resolve, reject) => {
    response.once('finish', resolve);
    response.once('error', reject);
  });
  const controller = new AdminController({
    getRaffleSummary: async () => ({
      from: '2026-10-01T00:00:00.000Z', to: '2026-10-31T23:59:59.999Z',
      participants: 1, tickets: 2, amountRub: 2000, ticketPriceRub: '1000',
    }),
    listRaffleTickets: async () => ({
      items: [
        { ticketNumber: '1', name: 'Иван', phone: '+79991111111' },
        { ticketNumber: '2', name: 'Иван', phone: '+79991111111' },
      ],
      nextCursor: null,
    }),
  } as any, {} as any);

  await controller.printRaffleTickets({
    from: '2026-10-01T00:00:00.000Z',
    to: '2026-10-31T23:59:59.999Z',
    ticketPrice: '1000',
  }, response as any);
  await finished;
  const pdf = Buffer.concat(chunks);

  assert.equal(pdf.subarray(0, 4).toString(), '%PDF');
  assert.ok(pdf.length > 1000);
  assert.equal(response.headers['Content-Type'], 'application/pdf');
});
