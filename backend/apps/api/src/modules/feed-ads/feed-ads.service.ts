import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { FeedAdPlacement } from '@prisma/client';
import { createHash } from 'crypto';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';

type FeedAdInput = Record<string, unknown>;
type CounterSource = { ip?: string; userAgent?: string };

const FEED_AD_IMPRESSION_DEBOUNCE_MS = 30 * 1000;
const FEED_AD_CLICK_DEBOUNCE_MS = 5 * 1000;

@Injectable()
export class FeedAdsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
    private readonly rateLimitService: RateLimitService,
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

  private normalizeTargetUrl(value: unknown) {
    const targetUrl = (value ?? '').toString().trim();
    if (!targetUrl) return '';

    let parsed: URL;
    try {
      parsed = new URL(targetUrl);
    } catch {
      throw new BadRequestException('Некорректная ссылка');
    }

    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      throw new BadRequestException('Некорректная ссылка');
    }

    return targetUrl;
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

  async getActive(placement?: string, afterId?: string) {
    const now = new Date();
    const items = await this.prisma.feedAd.findMany({
      where: {
        placement: this.placementFromInput(placement),
        isActive: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: [{ activatedAt: 'asc' }, { createdAt: 'asc' }],
      take: 3,
    });
    const cursor = (afterId ?? '').trim();
    const currentIndex = cursor
      ? items.findIndex((item) => item.id === cursor)
      : -1;
    const item =
      items.length === 0
        ? null
        : items[(currentIndex + 1 + items.length) % items.length];

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
        targetUrl: this.normalizeTargetUrl(body['target_url']),
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
          body['title'] == null
            ? undefined
            : (body['title'] ?? '').toString().trim(),
        imageUrl:
          body['image_url'] == null
            ? undefined
            : (body['image_url'] ?? '').toString().trim(),
        targetUrl:
          body['target_url'] == null
            ? undefined
            : this.normalizeTargetUrl(body['target_url']),
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

    if (!ad.isActive || (ad.expiresAt != null && ad.expiresAt <= now)) {
      const activeCount = await this.prisma.feedAd.count({
        where: {
          id: { not: id },
          placement: ad.placement,
          isActive: true,
          OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        },
      });

      if (activeCount >= 3) {
        throw new BadRequestException('Feed ads limit reached for placement');
      }
    }

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

  async recordImpression(id: string, source?: CounterSource) {
    const shouldCount = await this.shouldCountCounterEvent(
      'impression',
      id,
      source,
      FEED_AD_IMPRESSION_DEBOUNCE_MS,
    );
    if (!shouldCount) {
      return {
        tracked: true,
        id,
        event: 'impression',
      };
    }

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

  async recordClick(id: string, source?: CounterSource) {
    const shouldCount = await this.shouldCountCounterEvent(
      'click',
      id,
      source,
      FEED_AD_CLICK_DEBOUNCE_MS,
    );
    if (!shouldCount) {
      return {
        tracked: true,
        id,
        event: 'click',
      };
    }

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

  private shouldCountCounterEvent(
    event: 'impression' | 'click',
    id: string,
    source: CounterSource | undefined,
    windowMs: number,
  ) {
    const sourceKey = this.counterSourceKey(source);
    if (!sourceKey) {
      return Promise.resolve(true);
    }
    return this.rateLimitService.debounce(
      `feed-ad:${event}:${id}:${sourceKey}`,
      windowMs,
    );
  }

  private counterSourceKey(source?: CounterSource) {
    const ip = source?.ip?.trim();
    const userAgent = source?.userAgent?.trim();
    if (!ip && !userAgent) {
      return '';
    }
    return createHash('sha256')
      .update(`${ip || 'unknown'}:${userAgent || 'unknown'}`)
      .digest('hex');
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
