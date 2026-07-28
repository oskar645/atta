import { Injectable } from '@nestjs/common';
import { UserStatus } from '@prisma/client';
import { randomUUID } from 'crypto';

import { normalizeStoredMediaUrl, toIsoString } from '../../common/serializers';
import { PrismaService } from '../prisma/prisma.service';
import { WALLET_TIME_ZONE } from '../wallet/wallet.constants';

type TodayVisitRow = {
  id: string;
  display_name: string | null;
  name: string | null;
  phone: string | null;
  avatar_url: string | null;
  last_activity_at: Date;
  presence_is_online: boolean | null;
  presence_last_seen: Date | null;
};

@Injectable()
export class AppVisitsService {
  private readonly onlineTtlMs = 2 * 60 * 1000;

  constructor(private readonly prisma: PrismaService) {}

  async markAppOpened(userId: string, openedAt = new Date()) {
    const visitDate = this.getZonedDateStamp(openedAt);
    const visitId = randomUUID();
    await this.prisma.$executeRaw`
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
    const rows = await this.prisma.$queryRaw<Array<{ count: bigint }>>`
      SELECT COUNT(*)::bigint AS count
      FROM app_daily_visits adv
      INNER JOIN users u ON u.id = adv.user_id
      WHERE adv.visit_date = ${visitDate}::date
        AND u.deleted_at IS NULL
        AND u.status <> ${UserStatus.DELETED}::"UserStatus"
    `;
    return Number(rows[0]?.count ?? 0);
  }

  async listToday(now = new Date()) {
    const visitDate = this.getZonedDateStamp(now);
    const onlineCutoff = new Date(now.getTime() - this.onlineTtlMs);
    const [count, rows] = await Promise.all([
      this.countToday(now),
      this.prisma.$queryRaw<TodayVisitRow[]>`
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
          AND u.status <> ${UserStatus.DELETED}::"UserStatus"
        ORDER BY adv.last_activity_at DESC
        LIMIT 500
      `,
    ]);

    const items = rows.map((row) => {
      const lastSeenAt = row.presence_last_seen ?? null;
      const isOnline =
        row.presence_is_online === true &&
        lastSeenAt != null &&
        lastSeenAt >= onlineCutoff;

      return {
        id: row.id,
        display_name:
          row.display_name?.trim() ||
          row.name?.trim() ||
          row.phone?.trim() ||
          'Пользователь',
        name: row.name?.trim() || row.display_name?.trim() || 'Пользователь',
        phone: row.phone?.trim() || null,
        avatar_url: normalizeStoredMediaUrl(row.avatar_url, {
          category: 'avatars',
        }),
        is_online: isOnline,
        last_seen_at: toIsoString(lastSeenAt),
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

  private getZonedDateStamp(date: Date) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: WALLET_TIME_ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date);
    const values = Object.fromEntries(
      parts
        .filter((part) => part.type !== 'literal')
        .map((part) => [part.type, part.value]),
    );
    return `${values.year}-${values.month}-${values.day}`;
  }
}
