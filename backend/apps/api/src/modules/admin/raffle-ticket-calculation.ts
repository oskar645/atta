/** Amounts arrive from PostgreSQL numeric(12, 2), so calculate in kopeks. */
export function calculateRaffleTickets(totalRub: string, ticketPrice: string) {
  const [rubles, fractional = ''] = totalRub.split('.');
  const totalKopeks = BigInt(rubles) * 100n +
    BigInt(fractional.padEnd(2, '0').slice(0, 2));
  const ticketKopeks = BigInt(ticketPrice) * 100n;
  const tickets = totalKopeks / ticketKopeks;
  const remainderKopeks = totalKopeks % ticketKopeks;
  return {
    tickets: Number(tickets),
    remainderRub: Number(remainderKopeks) / 100,
  };
}
