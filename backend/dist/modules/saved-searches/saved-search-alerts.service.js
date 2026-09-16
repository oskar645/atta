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
var SavedSearchAlertsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SavedSearchAlertsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const listing_search_1 = require("../../common/listing-search");
const prisma_service_1 = require("../prisma/prisma.service");
const notifications_service_1 = require("../notifications/notifications.service");
const saved_search_matching_1 = require("./saved-search-matching");
let SavedSearchAlertsService = SavedSearchAlertsService_1 = class SavedSearchAlertsService {
    constructor(prisma, notifications) {
        this.prisma = prisma;
        this.notifications = notifications;
        this.logger = new common_1.Logger(SavedSearchAlertsService_1.name);
    }
    async notifyApprovedListing(listingId) {
        // No external queue/provider: publication stays successful if alert delivery
        // fails. Repeating approval safely retries missing records using the ledger.
        try {
            const listing = await this.prisma.listing.findFirst({ where: this.publicListing(listingId) });
            if (!listing)
                return;
            let cursor;
            for (;;) {
                const searches = await this.prisma.savedSearch.findMany({
                    where: { alertsEnabled: true, userId: { not: listing.ownerId }, createdAt: { lte: listing.publishedAt ?? listing.createdAt } },
                    orderBy: { id: 'asc' }, take: 100,
                    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
                });
                for (const candidate of searches) {
                    const item = await this.prisma.$transaction(async (tx) => {
                        // Serialize against deletion/disable and duplicate publication jobs.
                        await tx.$queryRaw `SELECT id FROM saved_searches WHERE id = ${candidate.id}::uuid FOR UPDATE`;
                        const search = await tx.savedSearch.findUnique({ where: { id: candidate.id } });
                        if (!search?.alertsEnabled)
                            return null;
                        await tx.$queryRaw `SELECT id FROM listings WHERE id = ${listingId}::uuid FOR SHARE`;
                        const current = await tx.listing.findFirst({
                            where: { ...this.publicListing(listingId), AND: [(0, listing_search_1.buildListingSearchWhere)(search.search) ?? {}] },
                        });
                        if (!current || current.ownerId === search.userId ||
                            search.createdAt > (current.publishedAt ?? current.createdAt) ||
                            !(0, saved_search_matching_1.matchesSavedSearchFilters)(current, search))
                            return null;
                        const inserted = await tx.savedSearchAlert.createMany({
                            data: [{ savedSearchId: search.id, listingId }], skipDuplicates: true,
                        });
                        if (inserted.count === 0)
                            return null;
                        return tx.userNotification.create({ data: {
                                userId: search.userId, scope: client_1.NotificationScope.PERSONAL, type: client_1.NotificationType.SAVED_SEARCH,
                                title: 'Новое объявление по вашему поиску',
                                body: `${search.title}: ${current.title}. ${current.price} ₽, ${current.city}.`,
                                payload: { actionType: 'saved_search', listingId, savedSearchId: search.id },
                            } });
                    });
                    if (item)
                        await this.notifications.publishNotification(item);
                }
                if (searches.length < 100)
                    break;
                cursor = searches[searches.length - 1].id;
            }
        }
        catch (error) {
            this.logger.error(`Saved search alerts failed listingId=${listingId} error=${error instanceof Error ? error.name : 'unknown'}`);
        }
    }
    publicListing(id) {
        return { id, status: client_1.ListingStatus.APPROVED, deletedAt: null,
            photos: { some: {} }, owner: { status: client_1.UserStatus.ACTIVE, deletedAt: null } };
    }
};
exports.SavedSearchAlertsService = SavedSearchAlertsService;
exports.SavedSearchAlertsService = SavedSearchAlertsService = SavedSearchAlertsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService, notifications_service_1.NotificationsService])
], SavedSearchAlertsService);
//# sourceMappingURL=saved-search-alerts.service.js.map