import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import {
  FeedAdPlacement,
  ListingStatus,
  NotificationType,
  PaymentProvider,
  PaymentStatus,
  Prisma,
  PromotionStatus,
  PromotionType,
  ReferralRewardStatus,
  SupportTicketStatus,
  UserBlockStatus,
  UserBlockType,
  UserStatus,
  WalletTransactionReason,
  WalletTransactionType,
} from '@prisma/client';

import { maskPhone } from '../../common/phone';
import { buildReferralCode, resolveReferralUserId } from '../../common/referral-code';
import {
  normalizeStoredMediaUrl,
  listingStatusFromInput,
  serializeListing,
  serializeUser,
  toIsoString,
} from '../../common/serializers';
import { AuthenticatedUser } from '../auth/auth.types';
import { AppVisitsService } from '../app-visits/app-visits.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { ReviewsService } from '../reviews/reviews.service';
import { StorageService } from '../storage/storage.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { promotionTypeToResponse } from '../promotions/promotion-plans.constants';
import { ArchiveListingDto } from '../listings/dto/archive-listing.dto';
import { LISTING_PHOTO_REQUIRED } from '../listings/listings.service';
import { BlockUserDto, UnblockUserDto, UpdateUserBlockDto } from './dto/block-user.dto';
import { ListAdminBonusAnalyticsDto } from './dto/list-admin-bonus-analytics.dto';
import { ListAdminPointsPurchasesDto } from './dto/list-admin-points-purchases.dto';
import { ListAdminPromotionsDto } from './dto/list-admin-promotions.dto';
import { ListAdminWalletTransactionsDto } from './dto/list-admin-wallet-transactions.dto';

const promotionStatusFromInput = (
  value?: string,
): PromotionStatus | undefined => {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'active':
      return PromotionStatus.ACTIVE;
    case 'expired':
      return PromotionStatus.EXPIRED;
    case 'cancelled':
      return PromotionStatus.CANCELLED;
    default:
      return undefined;
  }
};

const promotionTypeFromInput = (
  value?: string,
): PromotionType | undefined => {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'showcase':
      return PromotionType.SHOWCASE;
    case 'bump':
      return PromotionType.BUMP;
    case 'vip':
      return PromotionType.VIP;
    case 'turbo':
      return PromotionType.TURBO;
    default:
      return undefined;
  }
};

const walletTransactionTypeFromInput = (
  value?: string,
): WalletTransactionType | undefined => {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'accrual':
      return WalletTransactionType.ACCRUAL;
    case 'spend':
      return WalletTransactionType.SPEND;
    case 'refund':
      return WalletTransactionType.REFUND;
    default:
      return undefined;
  }
};

const protectedAdminPhones = new Set<string>([
  '79288888645',
  '79306939954',
]);

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly appVisitsService: AppVisitsService,
    private readonly notificationsService: NotificationsService,
    private readonly reviewsService: ReviewsService,
    private readonly storageService: StorageService,
    private readonly userBlocksService: UserBlocksService,
  ) {}

  async getDashboardStats() {
    const now = new Date();
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const days30 = new Date(now.getTime() - 30 * 86400000);
    const days14 = new Date(now.getTime() - 14 * 86400000);
    const onlineCutoff = new Date(now.getTime() - 2 * 60000);

    const [users, onlineUsers, todayVisits, listings, activeListings, pendingModeration, sold, sales30d, supportOpen, reportsOpen, activeAds, newListings14d, newListingsDaily, spentPoints30d, pointsPurchasesMonth] =
      await Promise.all([
        this.prisma.user.count({
          where: {
            deletedAt: null,
            status: {
              not: UserStatus.DELETED,
            },
          },
        }),
        this.prisma.userPresence.count({
          where: {
            isOnline: true,
            lastSeen: {
              gte: onlineCutoff,
            },
          },
        }),
        this.appVisitsService.countToday(now),
        this.prisma.listing.count({
          where: { deletedAt: null },
        }),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            status: ListingStatus.APPROVED,
          },
        }),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            archivedAt: null,
            status: ListingStatus.PENDING,
          },
        }),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            status: ListingStatus.SOLD,
          },
        }),
        this.prisma.listing.count({
          where: {
            deletedAt: null,
            status: ListingStatus.SOLD,
            updatedAt: {
              gte: days30,
            },
          },
        }),
        this.prisma.supportTicket.count(),
        this.prisma.report.count({
          where: { status: 'open' },
        }),
        this.prisma.feedAd.count({
          where: {
            placement: FeedAdPlacement.HOME,
            isActive: true,
            OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
          },
        }),
        this.prisma.listing.count({
          where: {
            createdAt: {
              gte: days14,
            },
          },
        }),
        this.prisma.listing.findMany({
          where: {
            createdAt: {
              gte: days14,
            },
          },
          select: {
            createdAt: true,
          },
        }),
        this.prisma.walletTransaction.aggregate({
          _sum: {
            amount: true,
          },
          where: {
            createdAt: {
              gte: days30,
              lte: now,
            },
            type: WalletTransactionType.SPEND,
          },
        }),
        this.getPointsPurchasesSummary({
          from: monthStart.toISOString(),
          to: now.toISOString(),
        }),
      ]);

    const dailyMap = new Map<string, number>();
    for (let index = 13; index >= 0; index -= 1) {
      const day = new Date(now.getTime() - index * 86400000);
      const key = day.toISOString().slice(0, 10);
      dailyMap.set(key, 0);
    }
    for (const item of newListingsDaily) {
      const key = item.createdAt.toISOString().slice(0, 10);
      dailyMap.set(key, (dailyMap.get(key) ?? 0) + 1);
    }
    const listingsDaily = Array.from(dailyMap.entries()).map(([day, count]) => ({
      day,
      listings_new: count,
    }));

    return {
      source: 'timeweb',
      stats: {
        users,
        onlineUsers,
        todayVisits,
        listings,
        activeListings,
        pendingModeration,
        sold,
        sales30d,
        supportTickets: supportOpen,
        supportOpen,
        reportsOpen,
        activeAds,
        newListings14d,
        spentPoints30d: spentPoints30d._sum.amount ?? 0,
        pointsPurchasesMonth,
      },
      daily: {
        listings: listingsDaily,
      },
    };
  }

  async listUsers() {
    const users = await this.prisma.user.findMany({
      where: {
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
      },
      include: {
        adminProfile: true,
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 100,
    });

    return {
      source: 'timeweb',
      items: users.map((user) => serializeUser(user, { includePrivate: true })),
    };
  }

  async listOnlineUsers() {
    const onlineCutoff = new Date(Date.now() - 2 * 60 * 1000);
    const users = await this.prisma.user.findMany({
      where: {
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
      },
      include: {
        presence: true,
      },
      take: 300,
    });

    const items = users
      .map((user) => {
        const lastSeenAt = user.presence?.lastSeen ?? null;
        const isOnline =
          user.presence?.isOnline === true &&
          lastSeenAt != null &&
          lastSeenAt >= onlineCutoff;

        return {
          id: user.id,
          display_name:
            user.displayName.trim() ||
            user.name.trim() ||
            user.phone?.trim() ||
            'Пользователь',
          name: user.name.trim() || user.displayName.trim() || 'Пользователь',
          phone: user.phone?.trim() || null,
          avatar_url: normalizeStoredMediaUrl(user.avatarUrl, {
            category: 'avatars',
          }),
          is_online: isOnline,
          last_seen_at: toIsoString(lastSeenAt),
        };
      })
      .filter((item) => item.is_online)
      .sort((left, right) => {
        const leftTime = Date.parse(left.last_seen_at ?? '1970-01-01T00:00:00.000Z');
        const rightTime = Date.parse(right.last_seen_at ?? '1970-01-01T00:00:00.000Z');
        return rightTime - leftTime;
      });

    return {
      source: 'timeweb',
      items,
    };
  }

  async listTodayVisits() {
    return this.appVisitsService.listToday();
  }

  async getUserById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      include: {
        adminProfile: true,
      },
    });

    return {
      source: 'timeweb',
      user: user ? serializeUser(user, { includePrivate: true }) : null,
    };
  }

  private resolveBlockDuration(dto: BlockUserDto, now: Date) {
    const duration = (dto.duration ?? '').trim().toLowerCase();
    if (duration === 'permanent' || duration === 'forever') {
      return {
        type: UserBlockType.PERMANENT,
        endsAt: null,
      };
    }
    if (duration === 'custom') {
      const endsAt = dto.ends_at ? new Date(dto.ends_at) : null;
      if (!endsAt || Number.isNaN(endsAt.getTime()) || endsAt <= now) {
        throw new BadRequestException('Укажите будущую дату окончания блокировки');
      }
      return {
        type: UserBlockType.TEMPORARY,
        endsAt,
      };
    }

    const daysByDuration: Record<string, number> = {
      one_day: 1,
      '1_day': 1,
      '1d': 1,
      seven_days: 7,
      '7_days': 7,
      '7d': 7,
      thirty_days: 30,
      '30_days': 30,
      '30d': 30,
    };
    const days = daysByDuration[duration];
    if (!days) {
      throw new BadRequestException('Неизвестный срок блокировки');
    }
    return {
      type: UserBlockType.TEMPORARY,
      endsAt: new Date(now.getTime() + days * 24 * 60 * 60 * 1000),
    };
  }

  private serializeAdminBlock(block: any) {
    const user = block.user
      ? serializeUser(block.user, { includePrivate: true })
      : null;
    return {
      ...this.userBlocksService.serializeBlock(block),
      user,
      listing: block.listing ? serializeListing(block.listing) : null,
      admin: block.admin
        ? serializeUser(block.admin, { includePrivate: true })
        : null,
      support_tickets_count: block._count?.appeals ?? 0,
      previous_blocks_count: block.user?._count?.blocks ?? 0,
      violations_count: block.user?._count?.blocks ?? 0,
    };
  }

  async listBlocks(status?: string) {
    const now = new Date();
    await this.prisma.userBlock.updateMany({
      where: {
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

    const normalized = (status ?? 'active').trim().toLowerCase();
    if (normalized === 'appeals') {
      const tickets = await this.prisma.supportTicket.findMany({
        where: {
          isBlockAppeal: true,
        },
        include: {
          userBlock: true,
        },
        orderBy: {
          updatedAt: 'desc',
        },
        take: 100,
      });
      return {
        source: 'timeweb',
        items: tickets.map((ticket) => ({
          id: ticket.id,
          ticket_id: ticket.id,
          user_id: ticket.userId,
          block_id: ticket.userBlockId,
          subject: ticket.subject,
          status: ticket.status.toLowerCase(),
          last_message: ticket.lastMessage,
          unread_for_admin: ticket.unreadForAdmin,
          created_at: ticket.createdAt.toISOString(),
          updated_at: ticket.updatedAt.toISOString(),
          block: this.userBlocksService.serializeBlock(ticket.userBlock),
        })),
      };
    }
    const where: Prisma.UserBlockWhereInput =
      normalized === 'history'
        ? {}
        : normalized === 'temporary'
          ? { type: UserBlockType.TEMPORARY, status: UserBlockStatus.ACTIVE }
          : normalized === 'permanent'
            ? { type: UserBlockType.PERMANENT, status: UserBlockStatus.ACTIVE }
            : normalized === 'finished' || normalized === 'completed'
              ? { status: { in: [UserBlockStatus.EXPIRED, UserBlockStatus.LIFTED] } }
              : { status: UserBlockStatus.ACTIVE };

    const blocks = await this.prisma.userBlock.findMany({
      where,
      include: {
        user: {
          include: {
            adminProfile: true,
            _count: {
              select: {
                blocks: true,
              },
            },
          },
        },
        listing: {
          include: {
            owner: {
              include: {
                adminProfile: true,
              },
            },
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
            },
          },
        },
        admin: {
          include: {
            adminProfile: true,
          },
        },
        _count: {
          select: {
            appeals: true,
          },
        },
      },
      orderBy: {
        startsAt: 'desc',
      },
      take: 100,
    });

    return {
      source: 'timeweb',
      items: blocks.map((block) => this.serializeAdminBlock(block)),
    };
  }

  async blockUser(
    userId: string,
    authUser: AuthenticatedUser,
    dto: BlockUserDto,
  ) {
    if (userId === authUser.userId) {
      throw new BadRequestException('Нельзя заблокировать текущий аккаунт администратора');
    }
    const reason = dto.reason?.trim() ?? '';
    if (!reason) {
      throw new BadRequestException('Причина блокировки обязательна');
    }
    const now = new Date();
    const duration = this.resolveBlockDuration(dto, now);
    const listingId = dto.listing_id?.trim() || undefined;

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, phone: true, deletedAt: true, status: true },
    });
    if (!user || user.deletedAt || user.status === UserStatus.DELETED) {
      throw new NotFoundException('Пользователь не найден');
    }

    const existing = await this.userBlocksService.getActiveBlock(userId);
    if (existing) {
      throw new BadRequestException('У пользователя уже есть активная блокировка');
    }

    const block = await this.prisma.$transaction(async (tx) => {
      const created = await tx.userBlock.create({
        data: {
          userId,
          listingId,
          adminId: authUser.userId,
          type: duration.type,
          status: UserBlockStatus.ACTIVE,
          reason,
          internalNote: dto.internal_note?.trim() || null,
          startsAt: now,
          endsAt: duration.endsAt,
        },
      });

      if (listingId) {
        await tx.listing.updateMany({
          where: { id: listingId, ownerId: userId },
          data: {
            status: ListingStatus.REJECTED,
            rejectionReason: reason,
            moderationNote: dto.internal_note?.trim() || reason,
            moderatedBy: authUser.userId,
            moderatedAt: now,
            publishedAt: null,
            archivedAt: null,
            deletedAt: null,
          },
        });
      }

      await tx.listing.updateMany({
        where: {
          ownerId: userId,
          status: ListingStatus.APPROVED,
        },
        data: {
          status: ListingStatus.ARCHIVED,
          archivedAt: now,
          publishedAt: null,
          moderationNote: 'Скрыто из ленты на время блокировки пользователя.',
        },
      });

      await tx.user.update({
        where: { id: userId },
        data: {
          status: UserStatus.BLOCKED,
          blockedAt: now,
          blockReason: reason,
        },
      });

      if (dto.ban_phone_identity === true && user.phone?.trim()) {
        await tx.blockedIdentity.create({
          data: {
            normalizedPhone: user.phone.trim(),
            userBlockId: created.id,
            bannedUntil: duration.endsAt,
            permanent: duration.type === UserBlockType.PERMANENT,
            reason,
          },
        });
      }

      await tx.auditLog.create({
        data: {
          actorUserId: authUser.userId,
          actorRole: 'admin',
          action: 'user.block',
          entityType: 'user',
          entityId: userId,
          newData: {
            blockId: created.id,
            listingId: listingId ?? null,
            duration: dto.duration,
            endsAt: duration.endsAt?.toISOString() ?? null,
          },
        },
      });

      return created;
    });

    await this.notificationsService.createSystemNotification({
      userId,
      title: 'Аккаунт заблокирован',
      body: reason,
      type: NotificationType.GENERIC,
      payload: {
        actionType: 'account_blocked',
        blockId: block.id,
        endsAt: duration.endsAt?.toISOString() ?? null,
        permanent: duration.type === UserBlockType.PERMANENT,
      },
    });

    return {
      source: 'timeweb',
      block: this.userBlocksService.serializeBlock(block),
    };
  }

  async unblockUserBlock(
    blockId: string,
    authUser: AuthenticatedUser,
    dto?: UnblockUserDto,
  ) {
    const block = await this.prisma.userBlock.findUnique({ where: { id: blockId } });
    if (!block) {
      throw new NotFoundException('Блокировка не найдена');
    }
    const now = new Date();
    const reason = dto?.reason?.trim() || 'Разблокировано администратором';

    const updated = await this.prisma.$transaction(async (tx) => {
      const lifted = await tx.userBlock.update({
        where: { id: blockId },
        data: {
          status: UserBlockStatus.LIFTED,
          liftedAt: now,
          liftedByAdminId: authUser.userId,
          liftReason: reason,
        },
      });
      await tx.blockedIdentity.updateMany({
        where: {
          userBlockId: blockId,
          liftedAt: null,
        },
        data: {
          liftedAt: now,
          liftedByAdminId: authUser.userId,
        },
      });
      const activeOther = await tx.userBlock.count({
        where: {
          userId: block.userId,
          id: { not: blockId },
          status: UserBlockStatus.ACTIVE,
          OR: [{ endsAt: null }, { endsAt: { gt: now } }],
        },
      });
      if (activeOther === 0) {
        await tx.user.update({
          where: { id: block.userId },
          data: {
            status: UserStatus.ACTIVE,
            blockedAt: null,
            blockReason: null,
          },
        });
      }
      await tx.auditLog.create({
        data: {
          actorUserId: authUser.userId,
          actorRole: 'admin',
          action: 'user.unblock',
          entityType: 'user',
          entityId: block.userId,
          newData: { blockId, reason },
        },
      });
      return lifted;
    });

    return {
      source: 'timeweb',
      block: this.userBlocksService.serializeBlock(updated),
    };
  }

  async updateUserBlock(
    blockId: string,
    authUser: AuthenticatedUser,
    dto: UpdateUserBlockDto,
  ) {
    const block = await this.prisma.userBlock.findUnique({ where: { id: blockId } });
    if (!block) {
      throw new NotFoundException('Блокировка не найдена');
    }
    if (block.status !== UserBlockStatus.ACTIVE) {
      throw new BadRequestException('Можно изменить только активную блокировку');
    }

    const now = new Date();
    const permanentRequested = dto.permanent === true;
    const temporaryRequested = dto.permanent === false || dto.ends_at != null;
    let nextType = block.type;
    let nextEndsAt = block.endsAt;

    if (permanentRequested) {
      nextType = UserBlockType.PERMANENT;
      nextEndsAt = null;
    } else if (temporaryRequested) {
      const endsAt = dto.ends_at ? new Date(dto.ends_at) : block.endsAt;
      if (!endsAt || Number.isNaN(endsAt.getTime()) || endsAt <= now) {
        throw new BadRequestException('Укажите будущую дату окончания блокировки');
      }
      nextType = UserBlockType.TEMPORARY;
      nextEndsAt = endsAt;
    }

    const changeReason = dto.reason?.trim() || 'Изменение срока блокировки';
    const internalNote =
      dto.internal_note === undefined
        ? block.internalNote
        : dto.internal_note.trim() || null;

    const updated = await this.prisma.$transaction(async (tx) => {
      const saved = await tx.userBlock.update({
        where: { id: blockId },
        data: {
          type: nextType,
          endsAt: nextEndsAt,
          internalNote,
        },
      });
      await tx.blockedIdentity.updateMany({
        where: {
          userBlockId: blockId,
          liftedAt: null,
        },
        data: {
          permanent: nextType === UserBlockType.PERMANENT,
          bannedUntil: nextType === UserBlockType.PERMANENT ? null : nextEndsAt,
        },
      });
      await tx.user.update({
        where: { id: block.userId },
        data: {
          status: UserStatus.BLOCKED,
          blockedAt: block.startsAt,
          blockReason: block.reason,
        },
      });
      await tx.auditLog.create({
        data: {
          actorUserId: authUser.userId,
          actorRole: 'admin',
          action: 'user.block.update',
          entityType: 'user',
          entityId: block.userId,
          newData: {
            blockId,
            reason: changeReason,
            previousEndsAt: block.endsAt?.toISOString() ?? null,
            nextEndsAt: nextEndsAt?.toISOString() ?? null,
            previousType: block.type,
            nextType,
          },
        },
      });
      return saved;
    });

    return {
      source: 'timeweb',
      block: this.userBlocksService.serializeBlock(updated),
    };
  }

  async deleteUser(id: string, authUser: AuthenticatedUser) {
    if (id === authUser.userId) {
      return {
        source: 'timeweb',
        deleted: false,
        message: 'Нельзя удалить текущий аккаунт администратора',
      };
    }

    const user = await this.prisma.user.findUnique({
      where: { id },
      include: {
        adminProfile: true,
      },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    if (protectedAdminPhones.has((user.phone ?? '').trim())) {
      return {
        source: 'timeweb',
        deleted: false,
        message: 'Этот администратор защищён от удаления',
      };
    }

    if (user.adminProfile?.isAdmin === true) {
      const adminsCount = await this.prisma.adminUser.count({
        where: {
          isAdmin: true,
        },
      });
      if (adminsCount <= 1) {
        return {
          source: 'timeweb',
          deleted: false,
          message: 'Нельзя удалить последнего администратора',
        };
      }
    }

    await this.performSoftDeleteUser(id, {
      actorUserId: authUser.userId,
      reason: 'Deleted by admin',
    });

    return {
      source: 'timeweb',
      deleted: true,
      user_id: id,
    };
  }

  async getModerationQueue(status?: string) {
    return this.listListings(status);
  }

  async listListings(status?: string) {
    const normalizedStatus = (status ?? '').trim().toLowerCase();
    const isPending =
      normalizedStatus === 'pending' || normalizedStatus.length === 0;
    const where: Prisma.ListingWhereInput = {
      deletedAt: null,
      ...(isPending ? { archivedAt: null } : {}),
      ...(normalizedStatus == 'all' || normalizedStatus.length === 0
        ? {}
        : { status: listingStatusFromInput(normalizedStatus) }),
    };
    const [items, total, pendingModeration] = await Promise.all([
      this.prisma.listing.findMany({
        where,
        include: {
          owner: {
            include: {
              adminProfile: true,
            },
          },
          photos: {
            orderBy: {
              sortOrder: 'asc',
            },
          },
        },
        orderBy: {
          createdAt: 'desc',
        },
        take: 100,
      }),
      this.prisma.listing.count({ where }),
      this.prisma.listing.count({
        where: {
          deletedAt: null,
          archivedAt: null,
          status: ListingStatus.PENDING,
        },
      }),
    ]);

    return {
      source: 'timeweb',
      items: items.map((listing) => serializeListing(listing)),
      total,
      pendingModeration,
      pending_moderation: pendingModeration,
      statuses: [
        'pending',
        'approved',
        'rejected',
        'sold',
        'deleted',
        'archived',
      ],
    };
  }

  async listPromotions(query: ListAdminPromotionsDto) {
    await this.expirePromotionsByTime();

    const range = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    const status = promotionStatusFromInput(query.status);
    const type = promotionTypeFromInput(query.type);
    const items = await this.prisma.promotion.findMany({
      where: {
        ...(status ? { status } : {}),
        ...(type ? { type } : {}),
        ...(query.userId?.trim() ? { userId: query.userId.trim() } : {}),
        ...(query.listingId?.trim()
          ? { listingId: query.listingId.trim() }
          : {}),
        ...(range ? { createdAt: range } : {}),
      },
      include: {
        listing: {
          include: {
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
            },
          },
        },
        user: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 200,
    });

    const now = Date.now();
    return {
      source: 'timeweb',
      items: items.map((promotion) => ({
        promotionId: promotion.id,
        type: promotionTypeToResponse(promotion.type),
        status: promotion.status.toLowerCase(),
        listingId: promotion.listingId,
        listingTitle: promotion.listing.title,
        listingPrice: Number(promotion.listing.price),
        listingPhoto: promotion.listing.photos[0]?.publicUrl ?? null,
        userId: promotion.userId,
        userName: promotion.user.displayName || promotion.user.name,
        userPhone: promotion.user.phone,
        costBonus: promotion.costBonus,
        startsAt: promotion.startsAt.toISOString(),
        endsAt: promotion.endsAt.toISOString(),
        timeRemainingSeconds: Math.max(
          0,
          Math.ceil((promotion.endsAt.getTime() - now) / 1000),
        ),
        impressionsCount: promotion.impressionsCount,
        clicksCount: promotion.clicksCount,
        createdAt: promotion.createdAt.toISOString(),
      })),
    };
  }

  async getPromotionsSummary() {
    await this.expirePromotionsByTime();

    const now = new Date();
    const startToday = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
    );
    const startMonth = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );

    const [
      activeShowcaseCount,
      activeBumpCount,
      activeVipCount,
      activeTurboCount,
      expiredTodayCount,
      spentToday,
      spentThisMonth,
      showcaseTotals,
    ] = await Promise.all([
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.SHOWCASE },
      }),
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.BUMP },
      }),
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.VIP },
      }),
      this.prisma.promotion.count({
        where: { status: PromotionStatus.ACTIVE, type: PromotionType.TURBO },
      }),
      this.prisma.promotion.count({
        where: {
          status: PromotionStatus.EXPIRED,
          endsAt: {
            gte: startToday,
            lte: now,
          },
        },
      }),
      this.prisma.promotion.aggregate({
        _sum: {
          costBonus: true,
        },
        where: {
          createdAt: {
            gte: startToday,
            lte: now,
          },
        },
      }),
      this.prisma.promotion.aggregate({
        _sum: {
          costBonus: true,
        },
        where: {
          createdAt: {
            gte: startMonth,
            lte: now,
          },
        },
      }),
      this.prisma.promotion.aggregate({
        _sum: {
          impressionsCount: true,
          clicksCount: true,
        },
        where: {
          type: PromotionType.SHOWCASE,
        },
      }),
    ]);

    return {
      source: 'timeweb',
      activeShowcaseCount,
      activeBumpCount,
      activeVipCount,
      activeTurboCount,
      expiredTodayCount,
      totalBonusSpentToday: spentToday._sum.costBonus ?? 0,
      totalBonusSpentThisMonth: spentThisMonth._sum.costBonus ?? 0,
      totalShowcaseImpressions: showcaseTotals._sum.impressionsCount ?? 0,
      totalShowcaseClicks: showcaseTotals._sum.clicksCount ?? 0,
    };
  }

  async cancelPromotion(id: string, authUser: AuthenticatedUser) {
    const promotion = await this.prisma.promotion.findUnique({
      where: {
        id,
      },
    });

    if (!promotion) {
      throw new NotFoundException('Promotion not found');
    }

    const updated = await this.prisma.promotion.update({
      where: {
        id,
      },
      data: {
        status: PromotionStatus.CANCELLED,
      },
    });

    return {
      source: 'timeweb',
      promotionId: updated.id,
      status: updated.status.toLowerCase(),
      cancelledBy: authUser.userId,
    };
  }

  async listWallets() {
    const wallets = await this.prisma.wallet.findMany({
      include: {
        user: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: {
        updatedAt: 'desc',
      },
      take: 200,
    });

    return {
      source: 'timeweb',
      items: wallets.map((wallet) => ({
        userId: wallet.userId,
        userName: wallet.user.displayName || wallet.user.name,
        userPhone: wallet.user.phone,
        bonusBalance: wallet.bonusBalance,
        lastBonusAccrualAt: toIsoString(wallet.lastBonusAccrualAt),
        createdAt: wallet.createdAt.toISOString(),
      })),
    };
  }

  async listWalletTransactions(query: ListAdminWalletTransactionsDto) {
    const range = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    const type = walletTransactionTypeFromInput(query.type);
    const reason = this.parseWalletReason(query.reason);
    const items = await this.prisma.walletTransaction.findMany({
      where: {
        ...(type ? { type } : {}),
        ...(reason ? { reason } : {}),
        ...(query.userId?.trim() ? { userId: query.userId.trim() } : {}),
        ...(range ? { createdAt: range } : {}),
      },
      include: {
        user: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 300,
    });

    return {
      source: 'timeweb',
      items: items.map((item) => ({
        transactionId: item.id,
        userId: item.userId,
        userName: item.user.displayName || item.user.name,
        userPhone: item.user.phone,
        type: item.type.toLowerCase(),
        amount: item.amount,
        reason: item.reason.toLowerCase(),
        metadata: item.metadata,
        createdAt: item.createdAt.toISOString(),
      })),
    };
  }

  async getBonusAnalytics(query: ListAdminBonusAnalyticsDto) {
    const range = this.resolveAnalyticsRange(query);
    const transactions = await this.prisma.walletTransaction.findMany({
      where: {
        createdAt: range,
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    const totalBonusAccrued = transactions
      .filter((item) => item.type === WalletTransactionType.ACCRUAL)
      .reduce((sum, item) => sum + item.amount, 0);
    const totalBonusSpent = transactions
      .filter((item) => item.type === WalletTransactionType.SPEND)
      .reduce((sum, item) => sum + item.amount, 0);
    const totalBonusRefunded = transactions
      .filter((item) => item.type === WalletTransactionType.REFUND)
      .reduce((sum, item) => sum + item.amount, 0);
    const spentByReason = {
      promotion_showcase: 0,
      promotion_bump: 0,
      promotion_vip: 0,
      promotion_turbo: 0,
    };

    const spendingUsers = new Set<string>();
    for (const item of transactions) {
      if (item.type === WalletTransactionType.SPEND) {
        spendingUsers.add(item.userId);
      }

      switch (item.reason) {
        case WalletTransactionReason.PROMOTION_SHOWCASE:
          spentByReason.promotion_showcase += item.amount;
          break;
        case WalletTransactionReason.PROMOTION_BUMP:
          spentByReason.promotion_bump += item.amount;
          break;
        case WalletTransactionReason.PROMOTION_VIP:
          spentByReason.promotion_vip += item.amount;
          break;
        case WalletTransactionReason.PROMOTION_TURBO:
          spentByReason.promotion_turbo += item.amount;
          break;
        default:
          break;
      }
    }

    const activeUsersWithWallet = await this.prisma.wallet.count({
      where: {
        bonusBalance: {
          gt: 0,
        },
      },
    });
    const fromDate =
      range.gte instanceof Date ? range.gte : new Date(range.gte);
    const toDate =
      range.lte instanceof Date ? range.lte : new Date(range.lte);

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      totalBonusAccrued,
      totalBonusSpent,
      totalBonusRefunded,
      spentByReason,
      activeUsersWithWallet,
      usersSpentBonusesCount: spendingUsers.size,
      note: 'Реальные платежи не подключены. Сейчас учитываются только бонусы.',
    };
  }

  async getPointsPurchasesSummary(query: ListAdminPointsPurchasesDto) {
    const { fromDate, toDate } = this.resolvePointsPurchasesRange(query);
    const search = (query.search ?? '').trim();
    const filters = this.buildPointsPurchaseFilters({ fromDate, toDate, search });
    const whereSql = Prisma.join(filters, ' AND ');
    const rows = await this.prisma.$queryRaw<
      Array<{
        total_amount_rub: string | number | null;
        total_points: bigint | number | null;
        purchases_count: bigint | number | null;
        unique_buyers_count: bigint | number | null;
      }>
    >`
      SELECT
        COALESCE(SUM(p."amount_rub"), 0)::text AS total_amount_rub,
        COALESCE(SUM(p."points_amount"), 0)::bigint AS total_points,
        COUNT(DISTINCT p."id")::bigint AS purchases_count,
        COUNT(DISTINCT p."user_id")::bigint AS unique_buyers_count
      FROM "payments" p
      JOIN "users" u ON u."id" = p."user_id"
      WHERE ${whereSql}
    `;
    const row = rows[0] ?? {
      total_amount_rub: 0,
      total_points: 0,
      purchases_count: 0,
      unique_buyers_count: 0,
    };

    return {
      source: 'timeweb',
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      totalAmountRub: this.numberFromDb(row.total_amount_rub),
      totalPoints: this.numberFromDb(row.total_points),
      purchasesCount: this.numberFromDb(row.purchases_count),
      uniqueBuyersCount: this.numberFromDb(row.unique_buyers_count),
    };
  }

  async listPointsPurchases(query: ListAdminPointsPurchasesDto) {
    const { fromDate, toDate } = this.resolvePointsPurchasesRange(query);
    const limit = Math.min(Math.max(query.limit ?? 30, 1), 100);
    const search = (query.search ?? '').trim();
    const cursor = this.decodePointsPurchaseCursor(query.cursor);
    const filters = this.buildPointsPurchaseFilters({ fromDate, toDate, search });
    if (cursor) {
      filters.push(Prisma.sql`(p."created_at", p."id") < (${cursor.createdAt}, ${cursor.id}::uuid)`);
    }
    const whereSql = Prisma.join(filters, ' AND ');
    const rows = await this.prisma.$queryRaw<
      Array<{
        payment_id: string;
        user_id: string;
        display_name: string | null;
        username: string | null;
        phone: string | null;
        amount_rub: string | number;
        points: number;
        status: string;
        created_at: Date;
      }>
    >`
      SELECT
        p."id"::text AS payment_id,
        p."user_id"::text AS user_id,
        u."display_name" AS display_name,
        NULLIF(u."name", '') AS username,
        u."phone" AS phone,
        p."amount_rub"::text AS amount_rub,
        p."points_amount" AS points,
        p."status"::text AS status,
        p."created_at" AS created_at
      FROM "payments" p
      JOIN "users" u ON u."id" = p."user_id"
      WHERE ${whereSql}
      ORDER BY p."created_at" DESC, p."id" DESC
      LIMIT ${limit + 1}
    `;

    const pageRows = rows.slice(0, limit);
    const next = rows.length > limit ? pageRows[pageRows.length - 1] : null;

    return {
      source: 'timeweb',
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      limit,
      nextCursor: next
        ? this.encodePointsPurchaseCursor({
            createdAt: next.created_at,
            id: next.payment_id,
          })
        : null,
      items: pageRows.map((row) => ({
        paymentId: row.payment_id,
        userId: row.user_id,
        displayName:
          row.display_name?.trim() ||
          row.username?.trim() ||
          row.phone?.trim() ||
          'Пользователь',
        username: row.username?.trim() || null,
        phone: row.phone?.trim() ? maskPhone(row.phone) : null,
        amountRub: this.numberFromDb(row.amount_rub),
        points: this.numberFromDb(row.points),
        status: 'Оплачено',
        createdAt: row.created_at.toISOString(),
      })),
    };
  }

  async getReferralSummary(query: ListAdminBonusAnalyticsDto) {
    const range = this.resolveAnalyticsRange(query);
    const [referrals, purchased, spent, daily] = await Promise.all([
      this.prisma.referral.findMany({
        where: {
          createdAt: range,
        },
      }),
      this.prisma.walletTransaction.aggregate({
        _sum: { amount: true },
        where: {
          createdAt: range,
          reason: WalletTransactionReason.POINTS_PURCHASE,
          type: WalletTransactionType.ACCRUAL,
        },
      }),
      this.prisma.walletTransaction.aggregate({
        _sum: { amount: true },
        where: {
          createdAt: range,
          type: WalletTransactionType.SPEND,
        },
      }),
      this.prisma.walletTransaction.aggregate({
        _sum: { amount: true },
        where: {
          createdAt: range,
          reason: WalletTransactionReason.DAILY_LOGIN_BONUS,
          type: WalletTransactionType.ACCRUAL,
        },
      }),
    ]);

    const rewarded = referrals.filter(
      (item) => item.rewardStatus === ReferralRewardStatus.REWARDED,
    );

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      newRegistrationsByInvite: referrals.filter((item) => item.registeredAt)
        .length,
      rewardedReferralBonuses: rewarded.length,
      referralPointsAwarded: rewarded.reduce(
        (sum, item) => sum + item.rewardAmount,
        0,
      ),
      unfinishedInvites: referrals.filter((item) => !item.registeredAt).length,
      rewardFailures: referrals.filter(
        (item) =>
          item.rewardStatus === ReferralRewardStatus.NOT_REWARDED ||
          item.rewardStatus === ReferralRewardStatus.FAILED_RETRYABLE,
      ).length,
      pointsPurchased: purchased._sum.amount ?? 0,
      pointsSpent: spent._sum.amount ?? 0,
      dailyBonusesAwarded: daily._sum.amount ?? 0,
    };
  }

  async listReferrals(query: ListAdminBonusAnalyticsDto & {
    search?: string;
    userId?: string;
  }) {
    const range = this.resolveAnalyticsRange(query);
    const search = query.search?.trim();
    const userId = query.userId?.trim();
    if (search || userId) {
      return this.listReferralUsers(query, range);
    }

    const referrals = await this.prisma.referral.findMany({
      where: {
        createdAt: range,
      },
      include: {
        inviter: {
          include: {
            adminProfile: true,
          },
        },
        invited: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 500,
    });

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      items: this.buildReferralUserItemsFromReferrals(referrals),
    };
  }

  async getUserReferrals(userId: string, query: ListAdminBonusAnalyticsDto) {
    const normalizedUserId = userId.trim();
    if (!this.isUuid(normalizedUserId)) {
      throw new NotFoundException('User not found');
    }

    const user = await this.prisma.user.findFirst({
      where: {
        id: normalizedUserId,
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
      },
      include: {
        adminProfile: true,
      },
    });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const range = this.resolveAnalyticsRange(query);
    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      item: await this.buildReferralUserItem(user, range),
    };
  }

  private async listReferralUsers(
    query: ListAdminBonusAnalyticsDto & {
      search?: string;
      userId?: string;
    },
    range: { gte: string | Date; lte: string | Date },
  ) {
    const search = query.search?.trim();
    const userId = query.userId?.trim();
    const searchLooksLikeUuid = search ? this.isUuid(search) : false;
    const decodedReferralUserId = search ? resolveReferralUserId(search) : null;
    const phoneDigits = (search ?? '').replace(/\D/g, '');
    const userSearchOr: Prisma.UserWhereInput[] = [
      ...(userId && this.isUuid(userId) ? [{ id: userId }] : []),
      ...(searchLooksLikeUuid ? [{ id: search }] : []),
      ...(decodedReferralUserId ? [{ id: decodedReferralUserId }] : []),
      ...(search
        ? [
            { displayName: { contains: search, mode: 'insensitive' as const } },
            { name: { contains: search, mode: 'insensitive' as const } },
            { phone: { contains: search } },
          ]
        : []),
      ...(phoneDigits.length >= 4 ? [{ phone: { contains: phoneDigits } }] : []),
    ];
    const matchingUsers = await this.prisma.user.findMany({
      where: {
        deletedAt: null,
        status: {
          not: UserStatus.DELETED,
        },
        ...(userSearchOr.length > 0
          ? { OR: userSearchOr }
          : { id: '00000000-0000-0000-0000-000000000000' }),
      },
      include: {
        adminProfile: true,
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 25,
    });

    return {
      source: 'timeweb',
      period: (query.period ?? 'month').trim().toLowerCase() || 'month',
      from: this.dateFilterValueToIso(range.gte),
      to: this.dateFilterValueToIso(range.lte),
      items: await Promise.all(
        matchingUsers.map((user) => this.buildReferralUserItem(user, range)),
      ),
    };
  }

  private buildReferralUserItemsFromReferrals(referrals: any[]) {
    const users = new Map<string, {
      inviter: Record<string, unknown>;
      referralCode: string;
      inviteLink: string;
      openedCount: number;
      registeredCount: number;
      rewardedCount: number;
      referralPoints: number;
      unfinishedCount: number;
      invitations: Array<Record<string, unknown>>;
    }>();

    for (const referral of referrals) {
      const key = referral.inviterUserId;
      const existing = users.get(key);
      const inviter = this.serializeReferralUser(referral.inviter);
      const item = existing ?? {
        inviter,
        referralCode: buildReferralCode(referral.inviterUserId),
        inviteLink: this.buildInviteLink(buildReferralCode(referral.inviterUserId)),
        openedCount: 0,
        registeredCount: 0,
        rewardedCount: 0,
        referralPoints: 0,
        unfinishedCount: 0,
        invitations: [] as Array<Record<string, unknown>>,
      };
      if (referral.openedAt || referral.appOpenedAt) item.openedCount += 1;
      if (referral.registeredAt || referral.invitedUserId) item.registeredCount += 1;
      if (referral.rewardStatus === ReferralRewardStatus.REWARDED) {
        item.rewardedCount += 1;
        item.referralPoints += referral.rewardAmount;
      }
      if (!referral.registeredAt && !referral.invitedUserId) {
        item.unfinishedCount += 1;
      }
      item.invitations.push(this.serializeReferral(referral));
      users.set(key, item);
    }

    return Array.from(users.values());
  }

  private async buildReferralUserItem(
    user: any,
    range: { gte: string | Date; lte: string | Date },
  ) {
    const referrals = await this.prisma.referral.findMany({
      where: {
        inviterUserId: user.id,
        createdAt: range,
      },
      include: {
        inviter: {
          include: {
            adminProfile: true,
          },
        },
        invited: {
          include: {
            adminProfile: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 500,
    });
    const referralCode = buildReferralCode(user.id);
    const item = {
      inviter: this.serializeReferralUser(user),
      referralCode,
      inviteLink: this.buildInviteLink(referralCode),
      openedCount: 0,
      registeredCount: 0,
      rewardedCount: 0,
      referralPoints: 0,
      unfinishedCount: 0,
      rejectedCount: 0,
      invitations: [] as Array<Record<string, unknown>>,
    };
    for (const referral of referrals) {
      if (referral.openedAt || referral.appOpenedAt) item.openedCount += 1;
      if (referral.registeredAt || referral.invitedUserId) item.registeredCount += 1;
      if (referral.rewardStatus === ReferralRewardStatus.REWARDED) {
        item.rewardedCount += 1;
        item.referralPoints += referral.rewardAmount;
      }
      if (!referral.registeredAt && !referral.invitedUserId) {
        item.unfinishedCount += 1;
      }
      if (
        referral.rewardStatus === ReferralRewardStatus.NOT_REWARDED ||
        referral.rewardStatus === ReferralRewardStatus.FAILED_RETRYABLE
      ) {
        item.rejectedCount += 1;
      }
      item.invitations.push(this.serializeReferral(referral));
    }
    return item;
  }

  async getReferralById(id: string) {
    const referral = await this.prisma.referral.findUnique({
      where: {
        id,
      },
      include: {
        inviter: {
          include: {
            adminProfile: true,
          },
        },
        invited: {
          include: {
            adminProfile: true,
          },
        },
      },
    });
    if (!referral) {
      throw new NotFoundException('Referral not found');
    }

    return {
      source: 'timeweb',
      item: this.serializeReferral(referral),
    };
  }

  async approveListing(id: string, authUser: AuthenticatedUser) {
    const listing = await this.prisma.listing.findUnique({
      where: { id },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }
    if (listing.photos.length === 0) {
      throw new BadRequestException(LISTING_PHOTO_REQUIRED);
    }

    const now = new Date();
    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.APPROVED,
        rejectionReason: null,
        moderationNote: null,
        moderatedBy: authUser.userId,
        moderatedAt: now,
        publishedAt: listing.publishedAt ?? now,
        archivedAt: null,
        deletedAt: null,
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    await this.notificationsService.createSystemNotification({
      userId: updated.ownerId,
      title: 'Объявление одобрено',
      body: `Объявление "${updated.title}" прошло модерацию.`,
      type: NotificationType.MODERATION,
      payload: {
        listingId: updated.id,
        status: 'approved',
      },
    });

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
    };
  }

  async rejectListing(
    id: string,
    authUser: AuthenticatedUser,
    params?: {
      reason?: string;
      moderationNote?: string;
    },
  ) {
    await this.ensureListingExists(id);

    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.REJECTED,
        rejectionReason: params?.reason?.trim() || 'Rejected by moderator',
        moderationNote: params?.moderationNote?.trim() || null,
        moderatedBy: authUser.userId,
        moderatedAt: new Date(),
        publishedAt: null,
        archivedAt: null,
        deletedAt: null,
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    await this.notificationsService.createSystemNotification({
      userId: updated.ownerId,
      title: 'Объявление отклонено',
      body: updated.rejectionReason ?? 'Объявление не прошло модерацию.',
      type: NotificationType.MODERATION,
      payload: {
        listingId: updated.id,
        status: 'rejected',
      },
    });

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
    };
  }

  async archiveListing(
    id: string,
    authUser: AuthenticatedUser,
    dto?: ArchiveListingDto,
  ) {
    await this.ensureListingExists(id);
    const nextStatus = dto?.status?.trim().toLowerCase() === 'sold'
      ? ListingStatus.SOLD
      : ListingStatus.ARCHIVED;
    const nextReason = dto?.note?.trim();

    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: nextStatus,
        rejectionReason:
          nextReason && nextReason.length > 0
            ? nextReason
            : nextStatus === ListingStatus.SOLD
              ? 'Объявление отмечено как проданное администратором.'
              : 'Объявление снято с публикации администратором.',
        moderatedBy: authUser.userId,
        moderatedAt: new Date(),
        archivedAt: new Date(),
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
      status_after_archive: nextStatus.toLowerCase(),
    };
  }

  async deleteListing(
    id: string,
    authUser: AuthenticatedUser,
    params?: {
      reason?: string;
      moderationNote?: string;
    },
  ) {
    await this.ensureListingExists(id);

    const updated = await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.DELETED,
        rejectionReason: params?.reason?.trim() || 'Deleted by moderator',
        moderationNote: params?.moderationNote?.trim() || null,
        moderatedBy: authUser.userId,
        moderatedAt: new Date(),
        deletedAt: new Date(),
        publishedAt: null,
      },
      include: {
        owner: {
          include: {
            adminProfile: true,
          },
        },
        photos: {
          orderBy: {
            sortOrder: 'asc',
          },
        },
      },
    });

    await this.notificationsService.createSystemNotification({
      userId: updated.ownerId,
      title: 'Объявление удалено',
      body: updated.rejectionReason ?? 'Объявление удалено модератором.',
      type: NotificationType.MODERATION,
      payload: {
        listingId: updated.id,
        status: 'deleted',
      },
    });

    await this.storageService.deleteListingPhotosForListings([id]);

    return {
      source: 'timeweb',
      listing: serializeListing(updated),
    };
  }

  async deleteReview(id: string, authUser: AuthenticatedUser) {
    return this.reviewsService.deleteReviewAsAdmin(authUser, id);
  }

  async getReportsPlaceholder() {
    const items = await this.prisma.report.findMany({
      orderBy: {
        createdAt: 'desc',
      },
      take: 100,
    });

    return {
      source: 'timeweb',
      items: items.map((report) => ({
        id: report.id,
        listing_id: report.listingId,
        listing_owner_id: report.listingOwnerId,
        reporter_id: report.reporterId,
        reason: report.reason,
        comment: report.comment,
        status: report.status,
        created_at: report.createdAt.toISOString(),
      })),
    };
  }

  async getSupportTicketsPlaceholder() {
    const items = await this.prisma.supportTicket.findMany({
      orderBy: {
        updatedAt: 'desc',
      },
      take: 100,
    });

    return {
      source: 'timeweb',
      items: items.map((ticket) => ({
        id: ticket.id,
        user_id: ticket.userId,
        name: ticket.name,
        subject: ticket.subject,
        status: ticket.status.toLowerCase(),
        unread_for_admin: ticket.unreadForAdmin,
        unread_for_user: ticket.unreadForUser,
        last_message: ticket.lastMessage,
        created_at: ticket.createdAt.toISOString(),
        updated_at: ticket.updatedAt.toISOString(),
      })),
    };
  }

  private async ensureListingExists(id: string) {
    const listing = await this.prisma.listing.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!listing) {
      throw new NotFoundException('Listing not found');
    }
  }

  private async performSoftDeleteUser(
    userId: string,
    params: {
      actorUserId: string;
      reason: string;
    },
  ) {
    const user = await this.prisma.user.findUnique({
      where: {
        id: userId,
      },
      select: {
        avatarUrl: true,
      },
    });
    const now = new Date();
    const deletedEmail = `deleted+${userId}@atta.local`;
    const listingIds = (
      await this.prisma.listing.findMany({
        where: {
          ownerId: userId,
        },
        select: {
          id: true,
        },
      })
    ).map((item) => item.id);
    const chatIds = (
      await this.prisma.chat.findMany({
        where: {
          OR: [{ buyerId: userId }, { sellerId: userId }],
        },
        select: {
          id: true,
        },
      })
    ).map((item) => item.id);

    await this.storageService.deleteAvatarUrl(user?.avatarUrl ?? null);
    await this.storageService.deleteListingPhotosForListings(listingIds);
    await this.storageService.deleteChatImagesForChats(chatIds);

    await this.prisma.$transaction(async (tx) => {
      if (chatIds.length > 0) {
        await tx.chatMessage.updateMany({
          where: {
            chatId: {
              in: chatIds,
            },
            deletedAt: null,
          },
          data: {
            deletedAt: now,
          },
        });
        await tx.chat.updateMany({
          where: {
            id: {
              in: chatIds,
            },
          },
          data: {
            deletedByBuyerAt: now,
            deletedBySellerAt: now,
            unreadForBuyer: 0,
            unreadForSeller: 0,
            lastMessage: '',
          },
        });
      }

      await tx.favorite.deleteMany({
        where: {
          userId,
        },
      });
      await tx.savedSearch.deleteMany({
        where: {
          userId,
        },
      });
      await tx.viewedListing.deleteMany({
        where: {
          userId,
        },
      });
      await tx.userFollow.deleteMany({
        where: {
          OR: [{ followerId: userId }, { sellerId: userId }],
        },
      });
      await tx.review.updateMany({
        where: {
          reviewerId: userId,
          deletedAt: null,
        },
        data: {
          deletedAt: now,
          updatedAt: now,
        },
      });
      await tx.userNotification.deleteMany({
        where: {
          userId,
        },
      });
      await tx.supportMessage.updateMany({
        where: {
          senderUserId: userId,
        },
        data: {
          senderUserId: null,
        },
      });
      await tx.supportTicket.updateMany({
        where: {
          userId,
        },
        data: {
          name: 'Удалённый пользователь',
        },
      });
      await tx.listing.updateMany({
        where: {
          ownerId: userId,
          deletedAt: null,
        },
        data: {
          status: ListingStatus.DELETED,
          deletedAt: now,
          publishedAt: null,
          moderatedBy: params.actorUserId,
          moderatedAt: now,
          rejectionReason: params.reason,
        },
      });
      await tx.userSession.updateMany({
        where: {
          userId,
          revokedAt: null,
        },
        data: {
          revokedAt: now,
        },
      });
      await tx.user.update({
        where: {
          id: userId,
        },
        data: {
          status: UserStatus.DELETED,
          deletedAt: now,
          blockedAt: now,
          blockReason: params.reason,
          phoneVerified: false,
          phone: null,
          email: deletedEmail,
          displayName: 'Удалённый пользователь',
          name: 'Удалённый пользователь',
          avatarUrl: null,
          photoUrl: null,
        },
      });
      if (listingIds.length > 0) {
        await tx.report.updateMany({
          where: {
            listingId: {
              in: listingIds,
            },
          },
          data: {
            listingOwnerId: null,
          },
        });
      }
    });
  }

  private async expirePromotionsByTime() {
    await this.prisma.promotion.updateMany({
      where: {
        status: PromotionStatus.ACTIVE,
        endsAt: {
          lte: new Date(),
        },
      },
      data: {
        status: PromotionStatus.EXPIRED,
      },
    });
  }

  private resolveRange(params: {
    from?: string;
    to?: string;
  }): Prisma.DateTimeFilter | undefined {
    const from = params.from ? new Date(params.from) : null;
    const to = params.to ? new Date(params.to) : null;
    const hasFrom = from != null && !Number.isNaN(from.getTime());
    const hasTo = to != null && !Number.isNaN(to.getTime());

    if (!hasFrom && !hasTo) {
      return undefined;
    }

    return {
      ...(hasFrom ? { gte: from! } : {}),
      ...(hasTo ? { lte: to! } : {}),
    };
  }

  private resolveAnalyticsRange(query: ListAdminBonusAnalyticsDto) {
    const explicit = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    if (explicit?.gte && explicit.lte) {
      return explicit as { gte: Date; lte: Date };
    }

    const now = new Date();
    const period = (query.period ?? 'month').trim().toLowerCase();
    let start = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );

    if (period === 'day') {
      start = new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
      );
    } else if (period === 'week') {
      start = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    }

    return {
      gte: explicit?.gte ?? start,
      lte: explicit?.lte ?? now,
    };
  }

  private resolvePointsPurchasesRange(query: Pick<ListAdminPointsPurchasesDto, 'from' | 'to'>) {
    const explicit = this.resolveRange({
      from: query.from,
      to: query.to,
    });
    const now = new Date();
    const monthStart = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );
    return {
      fromDate: (explicit?.gte as Date | undefined) ?? monthStart,
      toDate: (explicit?.lte as Date | undefined) ?? now,
    };
  }

  private buildPointsPurchaseFilters({
    fromDate,
    toDate,
    search,
  }: {
    fromDate: Date;
    toDate: Date;
    search: string;
  }) {
    const filters: Prisma.Sql[] = [
      Prisma.sql`p."provider" = ${PaymentProvider.YOOKASSA}::"PaymentProvider"`,
      Prisma.sql`p."status" = ${PaymentStatus.SUCCEEDED}::"PaymentStatus"`,
      Prisma.sql`p."credited_at" IS NOT NULL`,
      Prisma.sql`p."created_at" >= ${fromDate}`,
      Prisma.sql`p."created_at" <= ${toDate}`,
      Prisma.sql`EXISTS (
        SELECT 1
        FROM "wallet_transactions" wt
        WHERE wt."user_id" = p."user_id"
          AND wt."type" = ${WalletTransactionType.ACCRUAL}::"WalletTransactionType"
          AND wt."reason" = ${WalletTransactionReason.POINTS_PURCHASE}::"WalletTransactionReason"
          AND wt."amount" = p."points_amount"
          AND wt."metadata"->>'paymentId' = p."id"::text
      )`,
    ];
    const normalizedSearch = search.trim();
    if (normalizedSearch.length > 0) {
      const like = `%${normalizedSearch}%`;
      const digits = normalizedSearch.replace(/\D/g, '');
      filters.push(Prisma.sql`(
        p."user_id"::text ILIKE ${like}
        OR u."display_name" ILIKE ${like}
        OR u."name" ILIKE ${like}
        OR u."phone" ILIKE ${like}
        ${digits ? Prisma.sql`OR regexp_replace(COALESCE(u."phone", ''), '\\D', '', 'g') ILIKE ${`%${digits}%`}` : Prisma.empty}
      )`);
    }
    return filters;
  }

  private encodePointsPurchaseCursor(value: { createdAt: Date; id: string }) {
    return Buffer.from(
      JSON.stringify({
        createdAt: value.createdAt.toISOString(),
        id: value.id,
      }),
      'utf8',
    ).toString('base64url');
  }

  private decodePointsPurchaseCursor(cursor?: string) {
    const raw = (cursor ?? '').trim();
    if (!raw) return null;
    try {
      const decoded = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
      const createdAt = new Date(String(decoded.createdAt ?? ''));
      const id = String(decoded.id ?? '').trim();
      if (Number.isNaN(createdAt.getTime()) || !this.isUuid(id)) {
        return null;
      }
      return { createdAt, id };
    } catch {
      return null;
    }
  }

  private numberFromDb(value: unknown) {
    if (typeof value === 'bigint') return Number(value);
    if (typeof value === 'number') return value;
    const parsed = Number((value ?? '0').toString());
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseWalletReason(value?: string) {
    const normalized = (value ?? '').trim().toUpperCase();
    if (!normalized) {
      return undefined;
    }

    return Object.values(WalletTransactionReason).find(
      (item) => item === normalized,
    );
  }

  private dateFilterValueToIso(value: string | Date) {
    return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
  }

  private serializeReferral(referral: any) {
    return {
      id: referral.id,
      inviter: this.serializeReferralUser(referral.inviter),
      invited: referral.invited ? this.serializeReferralUser(referral.invited) : null,
      inviterUserId: referral.inviterUserId,
      invitedUserId: referral.invitedUserId,
      referralCode: referral.referralCode,
      inviteLink: this.buildInviteLink(referral.referralCode),
      openedAt: toIsoString(referral.openedAt),
      appOpenedAt: toIsoString(referral.appOpenedAt),
      signupStartedAt: toIsoString(referral.signupStartedAt),
      registeredAt: toIsoString(referral.registeredAt),
      registrationCompleted: Boolean(referral.registeredAt || referral.invitedUserId),
      isNewUser: referral.isNewUser,
      rewardStatus: referral.rewardStatus.toLowerCase(),
      rewardAmount: referral.rewardAmount,
      rewardedAt: toIsoString(referral.rewardedAt),
      bonusAwarded: referral.rewardStatus === ReferralRewardStatus.REWARDED,
      failureReason: referral.failureReason,
      failureText: this.referralFailureText(referral),
      walletTransactionId: referral.walletTransactionId,
      createdAt: referral.createdAt.toISOString(),
    };
  }

  private serializeReferralUser(user: any) {
    const displayName =
      user.displayName?.trim() ||
      user.name?.trim() ||
      user.phone?.trim() ||
      'Пользователь';
    return {
      id: user.id,
      name: displayName,
      displayName: user.displayName?.trim() || displayName,
      username: user.displayName?.trim() || null,
      phone: this.safePhone(user.phone),
      avatarUrl: normalizeStoredMediaUrl(user.avatarUrl ?? user.photoUrl, {
        category: 'avatars',
      }),
      referralCode: buildReferralCode(user.id),
      profilePath: `/admin/users/${user.id}`,
    };
  }

  private buildInviteLink(referralCode: string) {
    return `https://attamarket.online/invite?ref=${encodeURIComponent(referralCode)}`;
  }

  private safePhone(phone?: string | null) {
    const digits = (phone ?? '').replace(/\D/g, '');
    if (digits.length < 4) return phone?.trim() || null;
    return `${digits.slice(0, 1)}***${digits.slice(-4)}`;
  }

  private isUuid(value: string) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }

  private referralFailureText(referral: any) {
    if (referral.rewardStatus === ReferralRewardStatus.REWARDED) {
      return null;
    }
    if (!referral.registeredAt && !referral.invitedUserId) {
      return 'Ссылка открыта, но регистрация не завершена';
    }
    switch (referral.failureReason) {
      case 'APP_OPENED_WITHOUT_REFERRAL_CODE':
        return 'После установки приложение открыто без реферального кода';
      case 'USER_ALREADY_REGISTERED':
        return 'Пользователь уже был зарегистрирован';
      case 'SELF_REFERRAL':
        return 'Самоприглашение';
      case 'BONUS_ALREADY_AWARDED_FOR_INVITED_USER':
        return 'Бонус уже начислялся за этого пользователя';
      case 'REWARD_ERROR_RETRYABLE':
        return 'Ошибка начисления — требуется проверка';
      case 'INVALID_REFERRAL_CODE':
        return 'Реферальный код не распознан';
      case 'INVITER_NOT_FOUND':
        return 'Аккаунт пригласившего не найден';
      default:
        return referral.failureReason ? 'Бонус не начислен' : null;
    }
  }
}
