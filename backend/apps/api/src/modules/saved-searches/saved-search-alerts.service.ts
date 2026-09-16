import { Injectable, Logger } from '@nestjs/common';
import { ListingStatus, NotificationScope, NotificationType, UserStatus } from '@prisma/client';
import { buildListingSearchWhere } from '../../common/listing-search';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { matchesSavedSearchFilters } from './saved-search-matching';

@Injectable()
export class SavedSearchAlertsService {
  private readonly logger = new Logger(SavedSearchAlertsService.name);
  constructor(private readonly prisma: PrismaService, private readonly notifications: NotificationsService) {}

  async notifyApprovedListing(listingId: string) {
    // No external queue/provider: publication stays successful if alert delivery
    // fails. Repeating approval safely retries missing records using the ledger.
    try {
      const listing = await this.prisma.listing.findFirst({ where: this.publicListing(listingId) });
      if (!listing) return;
      let cursor: string | undefined;
      for (;;) {
        const searches = await this.prisma.savedSearch.findMany({
          where: { alertsEnabled: true, userId: { not: listing.ownerId }, createdAt: { lte: listing.publishedAt ?? listing.createdAt } },
          orderBy: { id: 'asc' }, take: 100,
          ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
        });
        for (const candidate of searches) {
          const item = await this.prisma.$transaction(async tx => {
            // Serialize against deletion/disable and duplicate publication jobs.
            await tx.$queryRaw`SELECT id FROM saved_searches WHERE id = ${candidate.id}::uuid FOR UPDATE`;
            const search = await tx.savedSearch.findUnique({ where: { id: candidate.id } });
            if (!search?.alertsEnabled) return null;
            await tx.$queryRaw`SELECT id FROM listings WHERE id = ${listingId}::uuid FOR SHARE`;
            const current = await tx.listing.findFirst({
              where: { ...this.publicListing(listingId), AND: [buildListingSearchWhere(search.search) ?? {}] },
            });
            if (!current || current.ownerId === search.userId ||
                search.createdAt > (current.publishedAt ?? current.createdAt) ||
                !matchesSavedSearchFilters(current, search)) return null;
            const inserted = await tx.savedSearchAlert.createMany({
              data: [{ savedSearchId: search.id, listingId }], skipDuplicates: true,
            });
            if (inserted.count === 0) return null;
            return tx.userNotification.create({ data: {
              userId: search.userId, scope: NotificationScope.PERSONAL, type: NotificationType.SAVED_SEARCH,
              title: 'Новое объявление по вашему поиску',
              body: `${search.title}: ${current.title}. ${current.price} ₽, ${current.city}.`,
              payload: { actionType: 'saved_search', listingId, savedSearchId: search.id },
            } });
          });
          if (item) await this.notifications.publishNotification(item);
        }
        if (searches.length < 100) break;
        cursor = searches[searches.length - 1].id;
      }
    } catch (error) {
      this.logger.error(`Saved search alerts failed listingId=${listingId} error=${error instanceof Error ? error.name : 'unknown'}`);
    }
  }

  private publicListing(id: string) {
    return { id, status: ListingStatus.APPROVED, deletedAt: null,
      photos: { some: {} }, owner: { status: UserStatus.ACTIVE, deletedAt: null } };
  }
}
