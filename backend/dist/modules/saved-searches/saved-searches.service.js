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
Object.defineProperty(exports, "__esModule", { value: true });
exports.SavedSearchesService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let SavedSearchesService = class SavedSearchesService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    parseNullableInt(value) {
        if (typeof value === 'number' && Number.isFinite(value)) {
            return Math.trunc(value);
        }
        const parsed = Number.parseInt((value ?? '').toString(), 10);
        return Number.isFinite(parsed) ? parsed : null;
    }
    async list(authUser) {
        const items = await this.prisma.savedSearch.findMany({
            where: {
                userId: authUser.userId,
            },
            orderBy: {
                updatedAt: 'desc',
            },
        });
        return {
            source: 'timeweb',
            items: items.map((item) => ({
                id: item.id,
                user_id: item.userId,
                title: item.title,
                query_key: item.queryKey,
                category: item.category,
                search: item.search,
                subcategory: item.subcategory,
                location: item.location,
                prefer_location_first: item.preferLocationFirst,
                radius_km: item.radiusKm,
                auto_brand: item.autoBrand,
                auto_model: item.autoModel,
                auto_condition: item.autoCondition,
                auto_mileage_to: item.autoMileageTo,
                only_uncrashed: item.onlyUncrashed,
                alerts_enabled: item.alertsEnabled,
                created_at: item.createdAt.toISOString(),
                updated_at: item.updatedAt.toISOString(),
            })),
        };
    }
    async upsert(authUser, body) {
        const item = await this.prisma.savedSearch.upsert({
            where: {
                userId_queryKey: {
                    userId: authUser.userId,
                    queryKey: (body['query_key'] ?? '').toString(),
                },
            },
            update: {
                title: (body['title'] ?? '').toString(),
                category: (body['category'] ?? 'Все').toString(),
                search: (body['search'] ?? '').toString(),
                subcategory: (body['subcategory'] ?? 'Все').toString(),
                location: (body['location'] ?? '').toString(),
                preferLocationFirst: body['prefer_location_first'] == true,
                radiusKm: this.parseNullableInt(body['radius_km']),
                autoBrand: (body['auto_brand'] ?? '').toString(),
                autoModel: (body['auto_model'] ?? '').toString(),
                autoCondition: (body['auto_condition'] ?? '').toString(),
                autoMileageTo: this.parseNullableInt(body['auto_mileage_to']),
                onlyUncrashed: body['only_uncrashed'] == true,
                alertsEnabled: body['alerts_enabled'] != false,
            },
            create: {
                userId: authUser.userId,
                title: (body['title'] ?? '').toString(),
                queryKey: (body['query_key'] ?? '').toString(),
                category: (body['category'] ?? 'Все').toString(),
                search: (body['search'] ?? '').toString(),
                subcategory: (body['subcategory'] ?? 'Все').toString(),
                location: (body['location'] ?? '').toString(),
                preferLocationFirst: body['prefer_location_first'] == true,
                radiusKm: this.parseNullableInt(body['radius_km']),
                autoBrand: (body['auto_brand'] ?? '').toString(),
                autoModel: (body['auto_model'] ?? '').toString(),
                autoCondition: (body['auto_condition'] ?? '').toString(),
                autoMileageTo: this.parseNullableInt(body['auto_mileage_to']),
                onlyUncrashed: body['only_uncrashed'] == true,
                alertsEnabled: body['alerts_enabled'] != false,
            },
        });
        return {
            source: 'timeweb',
            id: item.id,
        };
    }
    async remove(authUser, id) {
        await this.prisma.savedSearch.deleteMany({
            where: {
                id,
                userId: authUser.userId,
            },
        });
        return {
            deleted: true,
            id,
        };
    }
    async update(authUser, id, body) {
        await this.prisma.savedSearch.updateMany({
            where: {
                id,
                userId: authUser.userId,
            },
            data: {
                alertsEnabled: body['alerts_enabled'] == null
                    ? undefined
                    : body['alerts_enabled'] == true,
                title: body['title'] == null ? undefined : (body['title'] ?? '').toString(),
            },
        });
        return {
            source: 'timeweb',
            id,
            updated: true,
        };
    }
};
exports.SavedSearchesService = SavedSearchesService;
exports.SavedSearchesService = SavedSearchesService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], SavedSearchesService);
//# sourceMappingURL=saved-searches.service.js.map