import { Injectable, NotFoundException } from '@nestjs/common';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

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
  }) {
    return {
      id: report.id,
      listing_id: report.listingId,
      listing_owner_id: report.listingOwnerId,
      reporter_id: report.reporterId,
      reason: report.reason,
      comment: report.comment,
      status: report.status,
      decision: report.decision,
      admin_uid: report.adminUid,
      admin_comment: report.adminComment,
      created_at: report.createdAt.toISOString(),
    };
  }

  async listForAdmin() {
    const items = await this.prisma.report.findMany({
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      source: 'timeweb',
      items: items.map((report) => this.serialize(report)),
    };
  }

  async create(
    authUser: AuthenticatedUser,
    body: {
      listingId?: string;
      listingOwnerId?: string;
      reason?: string;
      comment?: string;
    },
  ) {
    const report = await this.prisma.report.create({
      data: {
        listingId: body.listingId?.trim() || null,
        listingOwnerId: body.listingOwnerId?.trim() || null,
        reporterId: authUser.userId,
        reason: body.reason?.trim() || 'Жалоба',
        comment: body.comment?.trim() || '',
        status: 'open',
      },
    });

    return {
      source: 'timeweb',
      item: this.serialize(report),
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
}
