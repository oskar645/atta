"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const listings_service_1 = require("./listings.service");
const ownerUser = {
    userId: 'owner-1',
    sessionId: 'session-1',
    role: 'user',
};
const strangerUser = {
    userId: 'user-2',
    sessionId: 'session-2',
    role: 'user',
};
function createService(overrides) {
    const prisma = {
        user: {
            findUnique: overrides?.findOwnerById ??
                (async () => ({
                    id: ownerUser.userId,
                    email: 'owner@example.com',
                    phone: '79281234567',
                    displayName: 'Owner',
                    name: 'Owner',
                    status: 'ACTIVE',
                })),
        },
        listing: {
            create: overrides?.create ??
                (async () => ({
                    id: 'listing-1',
                    ownerId: ownerUser.userId,
                    ownerEmail: 'owner@example.com',
                    ownerName: 'Owner',
                    title: 'Listing',
                    description: '',
                    category: 'misc',
                    subcategory: '',
                    price: BigInt(0),
                    phone: '79281234567',
                    phoneHidden: false,
                    city: '',
                    address: '',
                    locationJson: {},
                    delivery: {},
                    car: null,
                    status: client_1.ListingStatus.PENDING,
                    rejectionReason: '',
                    moderationNote: null,
                    moderatedBy: null,
                    moderatedAt: null,
                    publishedAt: null,
                    archivedAt: null,
                    deletedAt: null,
                    viewCount: 0,
                    createdAt: new Date(),
                    updatedAt: new Date(),
                    owner: {
                        id: ownerUser.userId,
                        email: 'owner@example.com',
                        phone: '79281234567',
                        phoneVerified: true,
                        displayName: 'Owner',
                        name: 'Owner',
                        avatarUrl: null,
                        photoUrl: null,
                        status: 'ACTIVE',
                        blockedAt: null,
                        blockReason: null,
                        lastLoginAt: null,
                        createdAt: new Date(),
                        updatedAt: new Date(),
                        deletedAt: null,
                        adminProfile: null,
                    },
                    photos: [],
                    promotions: [],
                })),
            findUnique: overrides?.findUnique ?? (async () => null),
            findMany: overrides?.findMany ?? (async () => []),
            update: overrides?.update ??
                (async (args) => ({
                    id: 'listing-1',
                    ownerId: 'owner-1',
                    title: 'Listing',
                    description: '',
                    category: 'misc',
                    subcategory: '',
                    price: BigInt(0),
                    phone: '',
                    phoneHidden: false,
                    city: '',
                    address: '',
                    locationJson: {},
                    delivery: {},
                    car: null,
                    status: client_1.ListingStatus.ARCHIVED,
                    rejectionReason: '',
                    moderationNote: null,
                    moderatedBy: null,
                    moderatedAt: null,
                    publishedAt: null,
                    archivedAt: new Date(),
                    deletedAt: null,
                    viewCount: 0,
                    createdAt: new Date(),
                    updatedAt: new Date(),
                    owner: null,
                    photos: [],
                    promotions: [],
                    ...args,
                })),
        },
        $transaction: async (handler) => handler(),
    };
    return new listings_service_1.ListingsService(prisma, {}, {});
}
(0, node_test_1.test)('owner cannot change listing status via generic update endpoint', async () => {
    const service = createService({
        findUnique: async () => ({
            id: 'listing-1',
            ownerId: ownerUser.userId,
            status: client_1.ListingStatus.APPROVED,
        }),
    });
    await strict_1.default.rejects(service.update('listing-1', ownerUser, { status: 'sold' }), common_1.ForbiddenException);
});
(0, node_test_1.test)('mark sold works through explicit archive endpoint', async () => {
    let updateArgs;
    const service = createService({
        findUnique: async () => ({
            id: 'listing-1',
            ownerId: ownerUser.userId,
            status: client_1.ListingStatus.APPROVED,
        }),
        update: async (args) => {
            updateArgs = args;
            return {
                id: 'listing-1',
                ownerId: ownerUser.userId,
                title: 'Listing',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.SOLD,
                rejectionReason: 'Продано владельцем.',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: null,
                archivedAt: new Date(),
                deletedAt: null,
                viewCount: 0,
                createdAt: new Date(),
                updatedAt: new Date(),
                owner: null,
                photos: [],
                promotions: [],
            };
        },
    });
    const response = await service.archive('listing-1', ownerUser, {
        status: 'sold',
        note: 'Продано владельцем.',
    });
    strict_1.default.equal(response.status_after_archive, 'sold');
    strict_1.default.equal((updateArgs?.data).status, client_1.ListingStatus.SOLD);
});
(0, node_test_1.test)('archive without sale works through explicit archive endpoint', async () => {
    let updateArgs;
    const service = createService({
        findUnique: async () => ({
            id: 'listing-1',
            ownerId: ownerUser.userId,
            status: client_1.ListingStatus.APPROVED,
        }),
        update: async (args) => {
            updateArgs = args;
            return {
                id: 'listing-1',
                ownerId: ownerUser.userId,
                title: 'Listing',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.ARCHIVED,
                rejectionReason: 'Снято владельцем с публикации.',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: null,
                archivedAt: new Date(),
                deletedAt: null,
                viewCount: 0,
                createdAt: new Date(),
                updatedAt: new Date(),
                owner: null,
                photos: [],
                promotions: [],
            };
        },
    });
    const response = await service.archive('listing-1', ownerUser, {
        status: 'archived',
    });
    strict_1.default.equal(response.status_after_archive, 'archived');
    strict_1.default.equal((updateArgs?.data).status, client_1.ListingStatus.ARCHIVED);
});
(0, node_test_1.test)('non-owner cannot archive listing through explicit endpoint', async () => {
    const service = createService({
        findUnique: async () => ({
            id: 'listing-1',
            ownerId: ownerUser.userId,
            status: client_1.ListingStatus.APPROVED,
        }),
    });
    await strict_1.default.rejects(service.archive('listing-1', strangerUser, { status: 'sold' }), common_1.ForbiddenException);
});
(0, node_test_1.test)('create uses owner phone when dto phone is empty', async () => {
    let createArgs;
    const service = createService({
        create: async (args) => {
            createArgs = args;
            return {
                id: 'listing-1',
                ownerId: ownerUser.userId,
                ownerEmail: 'owner@example.com',
                ownerName: 'Owner',
                title: 'Listing',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '79281234567',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.PENDING,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: null,
                archivedAt: null,
                deletedAt: null,
                viewCount: 0,
                createdAt: new Date(),
                updatedAt: new Date(),
                owner: {
                    id: ownerUser.userId,
                    email: 'owner@example.com',
                    phone: '79281234567',
                    phoneVerified: true,
                    displayName: 'Owner',
                    name: 'Owner',
                    avatarUrl: null,
                    photoUrl: null,
                    status: 'ACTIVE',
                    blockedAt: null,
                    blockReason: null,
                    lastLoginAt: null,
                    createdAt: new Date(),
                    updatedAt: new Date(),
                    deletedAt: null,
                    adminProfile: null,
                },
                photos: [],
                promotions: [],
            };
        },
    });
    const response = await service.create(ownerUser, {
        title: 'Listing',
        description: 'Desc',
        category: 'misc',
        subcategory: '',
        price: 1000,
        phone: '',
        phone_hidden: false,
        city: 'Grozny',
    });
    strict_1.default.equal((createArgs?.data).phone, '79281234567');
    strict_1.default.equal(response.listing.phone, '79281234567');
});
(0, node_test_1.test)('public feed is sorted by publishedAt desc, then createdAt desc, then id desc', async () => {
    const service = createService({
        findMany: async () => [
            {
                id: 'listing-a',
                ownerId: ownerUser.userId,
                ownerEmail: 'owner@example.com',
                ownerName: 'Owner',
                title: 'A',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: new Date('2026-06-19T10:00:05.000Z'),
                archivedAt: null,
                deletedAt: null,
                viewCount: 999,
                createdAt: new Date('2026-06-19T09:00:00.000Z'),
                updatedAt: new Date('2026-06-19T12:00:00.000Z'),
                owner: null,
                photos: [],
                promotions: [],
            },
            {
                id: 'listing-c',
                ownerId: ownerUser.userId,
                ownerEmail: 'owner@example.com',
                ownerName: 'Owner',
                title: 'C',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: new Date('2026-06-19T10:00:10.000Z'),
                archivedAt: null,
                deletedAt: null,
                viewCount: 0,
                createdAt: new Date('2026-06-19T08:00:00.000Z'),
                updatedAt: new Date('2026-06-19T08:30:00.000Z'),
                owner: null,
                photos: [],
                promotions: [],
            },
            {
                id: 'listing-b',
                ownerId: ownerUser.userId,
                ownerEmail: 'owner@example.com',
                ownerName: 'Owner',
                title: 'B',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: null,
                archivedAt: null,
                deletedAt: null,
                viewCount: 0,
                createdAt: new Date('2026-06-19T10:00:10.000Z'),
                updatedAt: new Date('2026-06-19T12:00:30.000Z'),
                owner: null,
                photos: [],
                promotions: [],
            },
        ],
    });
    const response = await service.findAll();
    strict_1.default.deepEqual(response.items.map((item) => item.id), ['listing-c', 'listing-a', 'listing-b']);
});
(0, node_test_1.test)('public feed fallback keeps later createdAt and larger id first when publishedAt matches', async () => {
    const sharedPublishedAt = new Date('2026-06-19T10:00:10.000Z');
    const sharedCreatedAt = new Date('2026-06-19T09:00:00.000Z');
    const service = createService({
        findMany: async () => [
            {
                id: 'listing-a',
                ownerId: ownerUser.userId,
                ownerEmail: 'owner@example.com',
                ownerName: 'Owner',
                title: 'A',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: sharedPublishedAt,
                archivedAt: null,
                deletedAt: null,
                viewCount: 0,
                createdAt: sharedCreatedAt,
                updatedAt: new Date('2026-06-19T12:00:00.000Z'),
                owner: null,
                photos: [],
                promotions: [],
            },
            {
                id: 'listing-b',
                ownerId: ownerUser.userId,
                ownerEmail: 'owner@example.com',
                ownerName: 'Owner',
                title: 'B',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: sharedPublishedAt,
                archivedAt: null,
                deletedAt: null,
                viewCount: 0,
                createdAt: sharedCreatedAt,
                updatedAt: new Date('2026-06-19T08:00:00.000Z'),
                owner: null,
                photos: [],
                promotions: [],
            },
        ],
    });
    const response = await service.findAll();
    strict_1.default.deepEqual(response.items.map((item) => item.id), ['listing-b', 'listing-a']);
});
(0, node_test_1.test)('listing photo upload uses selected storage provider flow', async () => {
    const storageCalls = [];
    const service = new listings_service_1.ListingsService({
        listing: {
            findUnique: async () => ({
                id: 'listing-1',
                ownerId: ownerUser.userId,
                photos: [],
            }),
            findUniqueOrThrow: async () => ({
                id: 'listing-1',
                ownerId: ownerUser.userId,
                title: 'Listing',
                description: '',
                category: 'misc',
                subcategory: '',
                price: BigInt(0),
                phone: '',
                phoneHidden: false,
                city: '',
                address: '',
                locationJson: {},
                delivery: {},
                car: null,
                status: client_1.ListingStatus.APPROVED,
                rejectionReason: '',
                moderationNote: null,
                moderatedBy: null,
                moderatedAt: null,
                publishedAt: null,
                archivedAt: null,
                deletedAt: null,
                viewCount: 0,
                createdAt: new Date(),
                updatedAt: new Date(),
                owner: null,
                photos: [],
                promotions: [],
            }),
        },
        listingPhoto: {
            create: async () => ({
                id: 'photo-1',
                publicUrl: 'https://s3.twcstorage.ru/atta-media-prod/listings/listing-1/photo.jpg',
                sortOrder: 0,
            }),
        },
    }, {
        saveUploadedFile: async (payload) => {
            storageCalls.push(payload);
            return {
                bucket: 'atta-media-prod',
                key: 'listings/listing-1/photo.jpg',
                mimeType: 'image/jpeg',
                provider: 's3',
                sizeBytes: 128,
                url: 'https://s3.twcstorage.ru/atta-media-prod/listings/listing-1/photo.jpg',
            };
        },
    }, {});
    const response = await service.uploadPhoto(ownerUser, 'listing-1', {
        buffer: Buffer.from('photo'),
        mimetype: 'image/jpeg',
        originalname: 'photo.jpg',
    });
    strict_1.default.equal(storageCalls.length, 1);
    strict_1.default.equal(storageCalls[0].category, 'listings');
    strict_1.default.deepEqual(storageCalls[0].context, {
        listingId: 'listing-1',
        userId: ownerUser.userId,
    });
    strict_1.default.match(response.photo.url, /listings\/listing-1\/photo\.jpg/);
});
//# sourceMappingURL=listings.service.spec.js.map