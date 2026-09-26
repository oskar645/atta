import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, TopBannerEventType } from '@prisma/client';
import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';

type Input = Record<string, unknown>;

@Injectable()
export class TopBannersService {
  constructor(private readonly prisma: PrismaService, private readonly storage: StorageService) {}

  private date(value: unknown, name: string) {
    const result = new Date(String(value ?? ''));
    if (Number.isNaN(result.getTime())) throw new BadRequestException(`Некорректное поле ${name}`);
    return result;
  }

  private url(value: unknown) {
    const raw = String(value ?? '').trim();
    if (!raw) return '';
    let parsed: URL;
    try { parsed = new URL(raw); } catch { throw new BadRequestException('Некорректная ссылка'); }
    if (parsed.protocol !== 'https:') throw new BadRequestException('Разрешены только HTTPS-ссылки');
    return raw;
  }

  private status(item: { enabled: boolean; startAt: Date; endAt: Date }, now = new Date()) {
    if (item.endAt <= now) return 'completed';
    if ('imageUrl' in item && !String(item.imageUrl ?? '').trim()) return 'draft';
    if (!item.enabled) return 'paused';
    if (item.startAt > now) return 'scheduled';
    return 'active';
  }

  private serialize(item: any) {
    const impressions = Number(item.impressionCount ?? 0);
    const clicks = Number(item.clickCount ?? 0);
    return { id: item.id, title: item.title, image_url: item.imageUrl, target_url: item.targetUrl,
      enabled: item.enabled, start_at: item.startAt.toISOString(), end_at: item.endAt.toISOString(),
      sort_order: item.sortOrder, status: this.status(item), impression_count: impressions,
      click_count: clicks, ctr: impressions ? clicks * 100 / impressions : 0,
      created_at: item.createdAt.toISOString(), updated_at: item.updatedAt.toISOString() };
  }

  private async require(id: string) {
    const item = await this.prisma.topBanner.findUnique({ where: { id } });
    if (!item) throw new NotFoundException('Верхний баннер не найден');
    return item;
  }

  async active(afterId?: string) {
    const now = new Date();
    const items = await this.prisma.topBanner.findMany({
      where: { enabled: true, startAt: { lte: now }, endAt: { gt: now }, imageUrl: { not: '' } },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }], take: 3,
    });
    const index = afterId ? items.findIndex((item) => item.id === afterId) : -1;
    const selected = items.length ? items[(index + 1 + items.length) % items.length] : null;
    return { source: 'timeweb', banner: selected ? this.serialize(selected) : null };
  }

  async list() {
    const items = await this.prisma.topBanner.findMany({ orderBy: [{ sortOrder: 'asc' }, { createdAt: 'desc' }] });
    return { source: 'timeweb', items: items.map((item) => this.serialize(item)) };
  }

  async create(user: AuthenticatedUser, body: Input) {
    const startAt = this.date(body['start_at'], 'start_at');
    const endAt = this.date(body['end_at'], 'end_at');
    if (endAt <= startAt) throw new BadRequestException('Окончание должно быть позже начала');
    const item = await this.prisma.topBanner.create({ data: { title: String(body['title'] ?? '').trim(),
      imageUrl: String(body['image_url'] ?? '').trim(), targetUrl: this.url(body['target_url']),
      enabled: false, startAt, endAt, sortOrder: Number(body['sort_order'] ?? 0), createdById: user.userId } });
    return { source: 'timeweb', banner: this.serialize(item) };
  }

  async update(id: string, body: Input) {
    const current = await this.require(id);
    const startAt = body['start_at'] == null ? current.startAt : this.date(body['start_at'], 'start_at');
    const endAt = body['end_at'] == null ? current.endAt : this.date(body['end_at'], 'end_at');
    if (endAt <= startAt) throw new BadRequestException('Окончание должно быть позже начала');
    const item = await this.prisma.topBanner.update({ where: { id }, data: {
      title: body['title'] == null ? undefined : String(body['title']).trim(),
      imageUrl: body['image_url'] == null ? undefined : String(body['image_url']).trim(),
      targetUrl: body['target_url'] == null ? undefined : this.url(body['target_url']), startAt, endAt,
      sortOrder: body['sort_order'] == null ? undefined : Number(body['sort_order']),
    }});
    return { source: 'timeweb', banner: this.serialize(item) };
  }

  async start(id: string) {
    const current = await this.require(id);
    if (!current.imageUrl.trim()) throw new BadRequestException('Сначала загрузите изображение');
    if (current.endAt <= new Date()) throw new BadRequestException('Сначала продлите срок баннера');
    return this.prisma.$transaction(async (tx) => {
      const count = await tx.topBanner.count({ where: { id: { not: id }, enabled: true,
        startAt: { lt: current.endAt }, endAt: { gt: current.startAt } } });
      if (count >= 3) throw new BadRequestException('Одновременно можно запустить не более 3 верхних баннеров');
      const item = await tx.topBanner.update({ where: { id }, data: { enabled: true } });
      return { source: 'timeweb', banner: this.serialize(item) };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  async stop(id: string) { await this.require(id); const item = await this.prisma.topBanner.update({ where: { id }, data: { enabled: false } }); return { source: 'timeweb', banner: this.serialize(item) }; }

  async extend(id: string, body: Input) {
    const current = await this.require(id);
    const base = current.endAt > new Date() ? current.endAt : new Date();
    const endAt = body['end_at'] != null ? this.date(body['end_at'], 'end_at') : new Date(base.getTime() + Number(body['days'] ?? 0) * 86400000);
    if (endAt <= new Date()) throw new BadRequestException('Новая дата окончания должна быть в будущем');
    const item = await this.prisma.topBanner.update({ where: { id }, data: { endAt } });
    return { source: 'timeweb', banner: this.serialize(item) };
  }

  async track(id: string, type: TopBannerEventType, rawSessionId: unknown) {
    const sessionId = String(rawSessionId ?? '').trim();
    if (!sessionId || sessionId.length > 100) throw new BadRequestException('Некорректная сессия');
    await this.require(id);
    try {
      await this.prisma.$transaction([
        this.prisma.topBannerEvent.create({ data: { bannerId: id, type, sessionId } }),
        this.prisma.topBanner.update({ where: { id }, data: type === 'IMPRESSION' ? { impressionCount: { increment: 1 } } : { clickCount: { increment: 1 } } }),
      ]);
    } catch (error) { if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')) throw error; }
    return { tracked: true, id, event: type.toLowerCase() };
  }

  async stats(id: string) {
    await this.require(id); const now = new Date();
    const since = (days: number) => new Date(now.getTime() - days * 86400000);
    const period = async (from?: Date) => { const where = { bannerId: id, ...(from ? { createdAt: { gte: from } } : {}) };
      const [impressions, clicks] = await Promise.all([
        this.prisma.topBannerEvent.count({ where: { ...where, type: 'IMPRESSION' } }),
        this.prisma.topBannerEvent.count({ where: { ...where, type: 'CLICK' } }),
      ]); return { impressions, clicks, ctr: impressions ? clicks * 100 / impressions : 0 }; };
    const startToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    return { total: await period(), today: await period(startToday), last_7_days: await period(since(7)), last_30_days: await period(since(30)) };
  }

  async attachImage(user: AuthenticatedUser, id: string, file: UploadedImageFile) {
    const current = await this.require(id);
    const uploaded = await this.storage.saveUploadedFile({ buffer: file.buffer, category: 'feed-ads', contentType: file.mimetype,
      context: { feedAdId: `top-${id}`, userId: user.userId }, originalName: file.originalname });
    if (current.imageKey) await this.storage.deleteStoredFile('feed-ads', current.imageKey, current.imageBucket);
    const item = await this.prisma.topBanner.update({ where: { id }, data: { imageUrl: uploaded.url, imageKey: uploaded.key, imageBucket: uploaded.bucket ?? 'local' } });
    return { source: 'timeweb', banner: this.serialize(item) };
  }

  async remove(id: string) { const current = await this.require(id); if (current.imageKey) await this.storage.deleteStoredFile('feed-ads', current.imageKey, current.imageBucket); await this.prisma.topBanner.delete({ where: { id } }); return { deleted: true, id }; }
}
