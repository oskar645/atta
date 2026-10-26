"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.calculateRaffleTickets = calculateRaffleTickets;
/** Amounts arrive from PostgreSQL numeric(12, 2), so calculate in kopeks. */
function calculateRaffleTickets(totalRub, ticketPrice) {
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
//# sourceMappingURL=raffle-ticket-calculation.js.map