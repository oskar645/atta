"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppVisitsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const serializers_1 = require("../../common/serializers");
const prisma_service_1 = require("../prisma/prisma.service");
const wallet_constants_1 = require("../wallet/wallet.constants");
let AppVisitsService = class AppVisitsService {
    constructor(prisma) {
        this.prisma = prisma;
        this.onlineTtlMs = 2 * 60 * 1000;
    }
    async markAppOpened(userId, openedAt = new Date()) {
        const visitDate = this.getZonedDateStamp(openedAt);
        const visitId = (0, crypto_1.randomUUID)();
        await this.prisma.$executeRaw `
      INSERT INTO app_daily_visits (id, user_id, visit_date, last_activity_at)
      VALUES (${visitId}::uuid, ${userId}::uuid, ${visitDate}::date, ${openedAt})
      ON CONFLICT (user_id, visit_date)
      DO UPDATE SET
        last_activity_at = EXCLUDED.last_activity_at,
        updated_at = CURRENT_TIMESTAMP
    `;
        return {
            source: 'timeweb',
            visit_date: visitDate,
            last_activity_at: openedAt.toISOString(),
        };
    }
    async countToday(now = new Date()) {
        const visitDate = this.getZonedDateStamp(now);
        const rows = await this.prisma.$queryRaw `
      SELECT COUNT(*)::bigint AS count
      FROM app_daily_visits adv
      INNER JOIN users u ON u.id = adv.user_id
      WHERE adv.visit_date = ${visitDate}::date
        AND u.deleted_at IS NULL
        AND u.status <> ${client_1.UserStatus.DELETED}::"UserStatus"
    `;
        return Number(rows[0]?.count ?? 0);
    }
    async listToday(now = new Date()) {
        const visitDate = this.getZonedDateStamp(now);
        const onlineCutoff = new Date(now.getTime() - this.onlineTtlMs);
        const [count, rows] = await Promise.all([
            this.countToday(now),
            this.prisma.$queryRaw `
        SELECT
          u.id,
          u.display_name,
          u.name,
          u.phone,
          u.avatar_url,
          adv.last_activity_at,
          up.is_online AS presence_is_online,
          up.last_seen AS presence_last_seen
        FROM app_daily_visits adv
        INNER JOIN users u ON u.id = adv.user_id
        LEFT JOIN user_presence up ON up.user_id = u.id
        WHERE adv.visit_date = ${visitDate}::date
          AND u.deleted_at IS NULL
          AND u.status <> ${client_1.UserStatus.DELETED}::"UserStatus"
        ORDER BY adv.last_activity_at DESC
        LIMIT 500
      `,
        ]);
        const items = rows.map((row) => {
            const lastSeenAt = row.presence_last_seen ?? null;
            const isOnline = row.presence_is_online === true &&
                lastSeenAt != null &&
                lastSeenAt >= onlineCutoff;
            return {
                id: row.id,
                display_name: row.display_name?.trim() ||
                    row.name?.trim() ||
                    row.phone?.trim() ||
                    'Пользователь',
                name: row.name?.trim() || row.display_name?.trim() || 'Пользователь',
                phone: row.phone?.trim() || null,
                avatar_url: (0, serializers_1.normalizeStoredMediaUrl)(row.avatar_url, {
                    category: 'avatars',
                }),
                is_online: isOnline,
                last_seen_at: (0, serializers_1.toIsoString)(lastSeenAt),
                last_activity_at: row.last_activity_at.toISOString(),
            };
        });
        return {
            source: 'timeweb',
            visit_date: visitDate,
            count,
            last_updated_at: now.toISOString(),
            items,
        };
    }
    getZonedDateStamp(date) {
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone: wallet_constants_1.WALLET_TIME_ZONE,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        }).formatToParts(date);
        const values = Object.fromEntries(parts
            .filter((part) => part.type !== 'literal')
            .map((part) => [part.type, part.value]));
        return `${values.year}-${values.month}-${values.day}`;
    }
};
exports.AppVisitsService = AppVisitsService;
exports.AppVisitsService = AppVisitsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], AppVisitsService);
//# sourceMappingURL=app-visits.service.js.map