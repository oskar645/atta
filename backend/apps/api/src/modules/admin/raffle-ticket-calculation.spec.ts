import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateRaffleTickets } from './raffle-ticket-calculation';

test('ticket allocation uses full tickets at the selected price', () => {
  const cases: Array<[string, string, number, number]> = [
    ['1000.00', '250', 4, 0],
    ['1000.00', '500', 2, 0],
    ['500.00', '1000', 0, 500],
    ['999.00', '1000', 0, 999],
    ['1000.00', '1000', 1, 0],
    ['2000.00', '1000', 2, 0],
    ['2500.00', '1000', 2, 500],
    ['5000.00', '1000', 5, 0],
    ['2000.00', '2100', 0, 2000],
    ['2100.00', '2100', 1, 0],
    ['4200.00', '2100', 2, 0],
    ['5000.00', '2100', 2, 800],
    ['10000.00', '2100', 4, 1600],
    ['1000.00', '100000000000000000000', 0, 1000],
  ];
  for (const [amount, price, tickets, remainderRub] of cases) {
    assert.deepEqual(calculateRaffleTickets(amount, price),
      { tickets, remainderRub }, `${amount} ₽ at ${price} ₽`);
  }
});

test('aggregated successful payments create a full ticket', () => {
  const total = (400 + 600).toFixed(2);
  assert.deepEqual(calculateRaffleTickets(total, '1000'),
    { tickets: 1, remainderRub: 0 });
});
