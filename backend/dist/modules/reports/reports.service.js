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
exports.ReportsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let ReportsService = class ReportsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    serialize(report) {
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
    async create(authUser, body) {
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
    async resolve(reportId, authUser, comment) {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
            },
        });
        if (!exists) {
            throw new common_1.NotFoundException('Report not found');
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
    async reject(reportId, authUser, comment) {
        const exists = await this.prisma.report.findUnique({
            where: {
                id: reportId,
            },
        });
        if (!exists) {
            throw new common_1.NotFoundException('Report not found');
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
};
exports.ReportsService = ReportsService;
exports.ReportsService = ReportsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], ReportsService);
//# sourceMappingURL=reports.service.js.map