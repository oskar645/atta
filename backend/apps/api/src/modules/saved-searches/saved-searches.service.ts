import { Injectable } from '@nestjs/common';

import { AuthenticatedUser } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class SavedSearchesService {
  constructor(private readonly prisma: PrismaService) {}

  private parseNullableInt(value: unknown): number | null {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.trunc(value);
    }

    const parsed = Number.parseInt((value ?? '').toString(), 10);
    return Number.isFinite(parsed) ? parsed : null;
  }

  async list(authUser: AuthenticatedUser) {
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

  async upsert(authUser: AuthenticatedUser, body: Record<string, unknown>) {
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

  async remove(authUser: AuthenticatedUser, id: string) {
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

  async update(
    authUser: AuthenticatedUser,
    id: string,
    body: Record<string, unknown>,
  ) {
    await this.prisma.savedSearch.updateMany({
      where: {
        id,
        userId: authUser.userId,
      },
      data: {
        alertsEnabled:
          body['alerts_enabled'] == null
            ? undefined
            : body['alerts_enabled'] == true,
        title:
          body['title'] == null ? undefined : (body['title'] ?? '').toString(),
      },
    });

    return {
      source: 'timeweb',
      id,
      updated: true,
    };
  }
}
