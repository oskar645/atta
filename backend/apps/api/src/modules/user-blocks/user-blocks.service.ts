import { ForbiddenException, Injectable } from '@nestjs/common';
import { UserBlockStatus, UserStatus } from '@prisma/client';

import { toIsoString } from '../../common/serializers';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UserBlocksService {
  constructor(private readonly prisma: PrismaService) {}

  serializeBlock(block: {
    id: string;
    userId: string;
    listingId?: string | null;
    adminId: string;
    type: string;
    status: string;
    reason: string;
    internalNote?: string | null;
    startsAt: Date;
    endsAt?: Date | null;
    liftedAt?: Date | null;
    liftedByAdminId?: string | null;
    liftReason?: string | null;
    createdAt: Date;
    updatedAt: Date;
  } | null) {
    if (!block) return null;
    return {
      id: block.id,
      user_id: block.userId,
      listing_id: block.listingId ?? null,
      admin_id: block.adminId,
      type: block.type.toLowerCase(),
      status: block.status.toLowerCase(),
      reason: block.reason,
      internal_note: block.internalNote ?? null,
      starts_at: block.startsAt.toISOString(),
      ends_at: toIsoString(block.endsAt),
      lifted_at: toIsoString(block.liftedAt),
      lifted_by_admin_id: block.liftedByAdminId ?? null,
      lift_reason: block.liftReason ?? null,
      permanent: block.type === 'PERMANENT',
      created_at: block.createdAt.toISOString(),
      updated_at: block.updatedAt.toISOString(),
    };
  }

  async getActiveBlock(userId: string) {
    const now = new Date();
    await this.prisma.userBlock.updateMany({
      where: {
        userId,
        status: UserBlockStatus.ACTIVE,
        endsAt: {
          not: null,
          lte: now,
        },
      },
      data: {
        status: UserBlockStatus.EXPIRED,
      },
    });
    await this.prisma.blockedIdentity.updateMany({
      where: {
        liftedAt: null,
        permanent: false,
        bannedUntil: {
          not: null,
          lte: now,
        },
      },
      data: {
        liftedAt: now,
      },
    });

    const block = await this.prisma.userBlock.findFirst({
      where: {
        userId,
        status: UserBlockStatus.ACTIVE,
        OR: [{ endsAt: null }, { endsAt: { gt: now } }],
      },
      orderBy: {
        startsAt: 'desc',
      },
    });

    if (!block) {
      await this.prisma.user.updateMany({
        where: {
          id: userId,
          status: UserStatus.BLOCKED,
        },
        data: {
          status: UserStatus.ACTIVE,
          blockedAt: null,
          blockReason: null,
        },
      });
    }

    return block;
  }

  async assertNotBlocked(userId: string) {
    const block = await this.getActiveBlock(userId);
    if (!block) return;

    throw new ForbiddenException({
      code: 'ACCOUNT_BLOCKED',
      message: 'Аккаунт заблокирован',
      blockId: block.id,
      reason: block.reason,
      endsAt: toIsoString(block.endsAt),
      permanent: block.type === 'PERMANENT',
    });
  }
}
