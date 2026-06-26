import { Injectable, NotFoundException } from '@nestjs/common';
import { FeedAdPlacement } from '@prisma/client';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';

type FeedAdInput = Record<string, unknown>;

@Injectable()
export class FeedAdsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
  ) {}

  private serialize(item: {
    id: string;
    title: string;
    imageUrl: string;
    targetUrl: string;
    durationDays: number;
    isActive: boolean;
    placement: FeedAdPlacement;
    createdAt: Date;
    activatedAt: Date | null;
    expiresAt: Date | null;
    updatedAt: Date | null;
    impressionCount: bigint;
    clickCount: bigint;
  }) {
    return {
      id: item.id,
      title: item.title,
      image_url: item.imageUrl,
      target_url: item.targetUrl,
      duration_days: item.durationDays,
      is_active: item.isActive,
      placement: item.placement.toLowerCase(),
      created_at: item.createdAt.toISOString(),
      activated_at: item.activatedAt?.toISOString() ?? null,
      expires_at: item.expiresAt?.toISOString() ?? null,
      updated_at: item.updatedAt?.toISOString() ?? null,
      impression_count: Number(item.impressionCount),
      click_count: Number(item.clickCount),
    };
  }

  private placementFromInput(value?: string) {
    return (value ?? '').trim().toLowerCase() === 'home'
      ? FeedAdPlacement.HOME
      : FeedAdPlacement.HOME;
  }

  async listAll(placement?: string) {
    const items = await this.prisma.feedAd.findMany({
      where: {
        placement: this.placementFromInput(placement),
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    return {
      source: 'timeweb',
      items: items.map((item) => this.serialize(item)),
    };
  }

  async getActive(placement?: string) {
    const now = new Date();
    const item = await this.prisma.feedAd.findFirst({
      where: {
        placement: this.placementFromInput(placement),
        isActive: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: [{ activatedAt: 'desc' }, { createdAt: 'desc' }],
    });

    return {
      source: 'timeweb',
      ad: item ? this.serialize(item) : null,
    };
  }

  async create(authUser: AuthenticatedUser, body: FeedAdInput) {
    const item = await this.prisma.feedAd.create({
      data: {
        title: (body['title'] ?? '').toString().trim(),
        imageUrl: (body['image_url'] ?? '').toString().trim(),
        targetUrl: (body['target_url'] ?? '').toString().trim(),
        durationDays: Number(body['duration_days'] ?? 0) || 0,
        isActive: body['is_active'] == true,
        placement: this.placementFromInput(body['placement']?.toString()),
        createdById: authUser.userId,
      },
    });

    return {
      source: 'timeweb',
      ad: this.serialize(item),
    };
  }

  async update(id: string, body: FeedAdInput) {
    await this.ensureExists(id);
    const item = await this.prisma.feedAd.update({
      where: { id },
      data: {
        title:
          body['title'] == null ? undefined : (body['title'] ?? '').toString().trim(),
        imageUrl:
          body['image_url'] == null
            ? undefined
            : (body['image_url'] ?? '').toString().trim(),
        targetUrl:
          body['target_url'] == null
            ? undefined
            : (body['target_url'] ?? '').toString().trim(),
        durationDays:
          body['duration_days'] == null
            ? undefined
            : Number(body['duration_days'] ?? 0) || 0,
      },
    });

    return {
      source: 'timeweb',
      ad: this.serialize(item),
    };
  }

  async activate(id: string) {
    const ad = await this.ensureExists(id);
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ad.durationDays * 86400000);

    await this.prisma.feedAd.updateMany({
      where: { placement: ad.placement },
      data: {
        isActive: false,
      },
    });

    const updated = await this.prisma.feedAd.update({
      where: { id },
      data: {
        isActive: true,
        activatedAt: now,
        expiresAt,
      },
    });

    return {
      source: 'timeweb',
      ad: this.serialize(updated),
    };
  }

  async deactivate(id: string) {
    await this.ensureExists(id);
    const updated = await this.prisma.feedAd.update({
      where: { id },
      data: {
        isActive: false,
      },
    });

    return {
      source: 'timeweb',
      ad: this.serialize(updated),
    };
  }

  async remove(id: string) {
    await this.ensureExists(id);
    await this.storageService.deleteFeedAdImage(id);
    await this.prisma.feedAd.delete({
      where: { id },
    });

    return {
      deleted: true,
      id,
    };
  }

  async recordImpression(id: string) {
    await this.prisma.feedAd.update({
      where: { id },
      data: {
        impressionCount: {
          increment: 1,
        },
      },
    });

    return {
      tracked: true,
      id,
      event: 'impression',
    };
  }

  async recordClick(id: string) {
    await this.prisma.feedAd.update({
      where: { id },
      data: {
        clickCount: {
          increment: 1,
        },
      },
    });

    return {
      tracked: true,
      id,
      event: 'click',
    };
  }

  private async ensureExists(id: string) {
    const item = await this.prisma.feedAd.findUnique({
      where: { id },
    });

    if (!item) {
      throw new NotFoundException('Feed ad not found');
    }

    return item;
  }

  async attachImage(
    authUser: AuthenticatedUser,
    feedAdId: string,
    file: UploadedImageFile,
  ) {
    await this.ensureExists(feedAdId);

    const uploaded = await this.storageService.saveUploadedFile({
      buffer: file.buffer,
      category: 'feed-ads',
      contentType: file.mimetype,
      context: {
        feedAdId,
        userId: authUser.userId,
      },
      originalName: file.originalname,
    });

    await this.storageService.deleteFeedAdImage(feedAdId);

    const item = await this.prisma.feedAd.update({
      where: {
        id: feedAdId,
      },
      data: {
        imageBucket: uploaded.bucket ?? 'local',
        imageKey: uploaded.key,
        imageUrl: uploaded.url,
        createdById: authUser.userId,
      },
    });

    return {
      source: 'timeweb',
      ad: this.serialize(item),
    };
  }
}
