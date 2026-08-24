import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { NotificationType } from '@prisma/client';

import { AuthenticatedUser } from '../auth/auth.types';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { ListAdminReportsDto } from './dto/list-admin-reports.dto';

@Injectable()
export class ReportsService {
  private static readonly hiddenStatuses = ['hidden', 'deleted'] as const;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

  private pageLimit(value: number | undefined, fallback = 50) {
    const parsed = Number(value ?? fallback);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(Math.max(Math.trunc(parsed), 1), 100);
  }

  private encodeAdminCursor(value: Record<string, string>) {
    return Buffer.from(JSON.stringify(value)).toString('base64url');
  }

  private decodeAdminCursor(cursor?: string) {
    const normalized = cursor?.trim();
    if (!normalized) return null;
    try {
      const parsed = JSON.parse(
        Buffer.from(normalized, 'base64url').toString('utf8'),
      );
      if (!parsed || typeof parsed !== 'object') return null;
      return parsed as Record<string, string>;
    } catch {
      return null;
    }
  }

  private serialize(report: {
    id: string;
    listingId: string | null;
    listingOwnerId: string | null;
    reporterId: string;
    reason: string;
    comment: string;
    status: string;
    decision: string | null;
    adminUid: string | null;
    adminComment: string | null;
    createdAt: Date;
    handledAt?: Date | null;
    closedAt?: Date | null;
    listing?: {
      id: string;
      title: string;
      ownerId: string;
      owner?: {
        id: string;
        displayName: string;
        name: string;
      } | null;
      photos?: Array<{
        id?: string;
        url?: string | null;
        publicUrl?: string | null;
        storageKey?: string | null;
        sortOrder?: number | null;
      }>;
    } | null;
    reporter?: {
      id: string;
      displayName: string;
      name: string;
      avatarUrl?: string | null;
      photoUrl?: string | null;
    } | null;
    listingOwner?: {
      id: string;
      displayName: string;
      name: string;
      avatarUrl?: string | null;
      photoUrl?: string | null;
    } | null;
  }) {
    const listingPhotos =
      report.listing?.photos?.map((photo) => ({
        id: photo.id ?? null,
        url: photo.url ?? photo.publicUrl ?? null,
        publicUrl: photo.publicUrl ?? photo.url ?? null,
        storageKey: photo.storageKey ?? null,
        sortOrder: photo.sortOrder ?? null,
      })) ?? [];
    const targetType = report.listingId ? 'listing' : 'user';
    const listingPhotoUrl = listingPhotos[0]?.url ?? null;
    return {
      id: report.id,
      listing_id: report.listingId,
      listing_owner_id: report.listingOwnerId,
      reported_user_id: report.listingOwnerId,
      reporter_id: report.reporterId,
      reason: report.reason,
      comment: report.comment,
      status: report.status,
      decision: report.decision,
      admin_uid: report.adminUid,
      admin_comment: report.adminComment,
      created_at: report.createdAt.toISOString(),
      handled_at: report.handledAt?.toISOString() ?? null,
      closed_at: report.closedAt?.toISOString() ?? null,
      target_type: targetType,
      listing_title: report.listing?.title ?? null,
      listing_photo_url: listingPhotoUrl,
      listing_photos: listingPhotos,
      listing_seller_id: report.listing?.ownerId ?? report.listingOwnerId,
      listing_seller_name:
        report.listing?.owner?.displayName?.trim() ||
        report.listing?.owner?.name?.trim() ||
        report.listingOwner?.displayName?.trim() ||
        report.listingOwner?.name?.trim() ||
        null,
      reporter_name:
        report.reporter?.displayName?.trim() ||
        report.reporter?.name?.trim() ||
        null,
      reporter_avatar_url:
        report.reporter?.avatarUrl?.trim() ||
        report.reporter?.photoUrl?.trim() ||
        null,
      reported_user_name:
        report.listingOwner?.displayName?.trim() ||
        report.listingOwner?.name?.trim() ||
        null,
      reported_user_avatar_url:
        report.listingOwner?.avatarUrl?.trim() ||
        report.listingOwner?.photoUrl?.trim() ||
        null,
    };
  }

  async listForAdmin(query: ListAdminReportsDto = {}) {
    const limit = this.pageLimit(query.limit);
    const decoded = this.decodeAdminCursor(query.cursor);
    const rawCreatedAt = decoded?.createdAt;
    const cursorDate = rawCreatedAt ? new Date(rawCreatedAt) : null;
    const cursorId = decoded?.id;
    const items = await this.prisma.report.findMany({
      where: {
        status: {
          notIn: [...ReportsService.hiddenStatuses],
        },
        ...(cursorDate && !Number.isNaN(cursorDate.getTime()) && cursorId
          ? {
              OR: [
                { createdAt: { lt: cursorDate } },
                { createdAt: cursorDate, id: { lt: cursorId } },
              ],
            }
          : {}),
      },
      include: {
        listing: {
          include: {
            owner: true,
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
              take: 1,
            },
          },
        },
        listingOwner: true,
        reporter: true,
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const pageItems = items.slice(0, limit);
    const last = items.length > limit ? pageItems[pageItems.length - 1] : null;

    return {
      source: 'timeweb',
      items: pageItems.map((report) => this.serialize(report)),
      nextCursor: last
        ? this.encodeAdminCursor({
            createdAt: last.createdAt.toISOString(),
            id: last.id,
          })
        : null,
      hasMore: items.length > limit,
      limit,
    };
  }

  async create(
    authUser: AuthenticatedUser,
    body: {
      listingId?: string;
      listingOwnerId?: string;
      reportedUserId?: string;
      reason?: string;
      comment?: string;
    },
  ) {
    const listingId = body.listingId?.trim() || null;
    let reportedUserId =
      body.reportedUserId?.trim() || body.listingOwnerId?.trim() || null;
    if (listingId) {
      const listing = await this.prisma.listing.findUnique({
        where: {
          id: listingId,
        },
        select: {
          ownerId: true,
        },
      });
      if (!listing) {
        throw new BadRequestException('Объявление для жалобы не найдено');
      }
      reportedUserId = listing.ownerId;
    }
    if (!listingId && !reportedUserId) {
      throw new BadRequestException('Нужно указать объявление или пользователя для жалобы');
    }
    const report = await this.prisma.report.create({
      data: {
        listingId,
        listingOwnerId: reportedUserId,
        reporterId: authUser.userId,
        reason: body.reason?.trim() || 'Жалоба',
        comment: body.comment?.trim() || '',
        status: 'open',
      },
      include: {
        listing: {
          include: {
            owner: true,
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
              take: 1,
            },
          },
        },
        listingOwner: true,
        reporter: true,
      },
    });

    const admins = await this.prisma.adminUser.findMany({
      select: {
        userId: true,
      },
    });
    const adminNotifications = await Promise.all(
      admins.map(({ userId }) =>
        this.notificationsService.createSystemNotification({
          userId,
          title: 'Новая жалоба',
          body:
            report.reason.trim().length > 0
              ? `Поступила новая жалоба: ${report.reason.trim()}.`
              : 'Поступила новая жалоба.',
          type: NotificationType.GENERIC,
          payload: {
            actionType: 'admin_report_new',
            reportId: report.id,
          },
        }),
      ),
    );

    return {
      source: 'timeweb',
      item: this.serialize(report),
      admin_notifications: adminNotifications.map((item) =>
        this.notificationsService.serializeNotification(item),
      ),
    };
  }

  async resolve(reportId: string, authUser: AuthenticatedUser, comment?: string) {
    const exists = await this.prisma.report.findUnique({
      where: {
        id: reportId,
      },
    });

    if (!exists) {
      throw new NotFoundException('Report not found');
    }

    const report = await this.prisma.report.update({
      where: {
        id: reportId,
      },
      data: {
        status: 'resolved',
        decision: 'resolved',
        adminUid: authUser.userId,
        adminComment: comment?.trim() || null,
        handledBy: authUser.userId,
        handledAt: new Date(),
        closedAt: new Date(),
      },
    });

    return {
      source: 'timeweb',
      item: this.serialize(report),
    };
  }

  async reject(reportId: string, authUser: AuthenticatedUser, comment?: string) {
    const exists = await this.prisma.report.findUnique({
      where: {
        id: reportId,
      },
    });

    if (!exists) {
      throw new NotFoundException('Report not found');
    }

    const report = await this.prisma.report.update({
      where: {
        id: reportId,
      },
      data: {
        status: 'rejected',
        decision: 'rejected',
        adminUid: authUser.userId,
        adminComment: comment?.trim() || null,
        handledBy: authUser.userId,
        handledAt: new Date(),
        closedAt: new Date(),
      },
    });

    return {
      source: 'timeweb',
      item: this.serialize(report),
    };
  }

  async reopen(reportId: string, authUser: AuthenticatedUser) {
    const exists = await this.prisma.report.findUnique({
      where: {
        id: reportId,
      },
      include: {
        listing: {
          include: {
            owner: true,
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
              take: 1,
            },
          },
        },
        listingOwner: true,
        reporter: true,
      },
    });

    if (!exists) {
      throw new NotFoundException('Report not found');
    }

    const report = await this.prisma.report.update({
      where: {
        id: reportId,
      },
      data: {
        status: 'open',
        decision: null,
        adminUid: authUser.userId,
        adminComment: null,
        handledBy: authUser.userId,
        handledAt: new Date(),
        closedAt: null,
      },
      include: {
        listing: {
          include: {
            owner: true,
            photos: {
              orderBy: {
                sortOrder: 'asc',
              },
              take: 1,
            },
          },
        },
        listingOwner: true,
        reporter: true,
      },
    });

    return {
      source: 'timeweb',
      item: this.serialize(report),
    };
  }

  async hide(reportId: string, authUser: AuthenticatedUser) {
    const exists = await this.prisma.report.findUnique({
      where: {
        id: reportId,
      },
    });

    if (!exists) {
      throw new NotFoundException('Жалоба не найдена');
    }

    const report = await this.prisma.report.update({
      where: {
        id: reportId,
      },
      data: {
        status: 'hidden',
        decision: exists.decision ?? 'hidden',
        adminUid: authUser.userId,
        handledBy: authUser.userId,
        handledAt: exists.handledAt ?? new Date(),
        closedAt: exists.closedAt ?? new Date(),
      },
    });

    return {
      source: 'timeweb',
      hidden: true,
      item: this.serialize(report),
    };
  }
}
