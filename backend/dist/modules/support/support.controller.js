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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminSupportController = exports.SupportController = void 0;
const common_1 = require("@nestjs/common");
const platform_express_1 = require("@nestjs/platform-express");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const create_support_ticket_dto_1 = require("./dto/create-support-ticket.dto");
const list_admin_support_tickets_dto_1 = require("./dto/list-admin-support-tickets.dto");
const send_support_message_dto_1 = require("./dto/send-support-message.dto");
const support_service_1 = require("./support.service");
const memoryImageUpload = (0, platform_express_1.FileInterceptor)('file', {
    storage: require('multer').memoryStorage(),
});
let SupportController = class SupportController {
    constructor(supportService, rateLimitService) {
        this.supportService = supportService;
        this.rateLimitService = rateLimitService;
    }
    rateKey(userId, ticketId) {
        return `support:${userId}:${ticketId}`;
    }
    listTickets(authUser) {
        return this.supportService.listMyTickets(authUser);
    }
    async uploadImage(authUser, request, file) {
        await this.rateLimitService.consumeOrThrow(`support:image:${authUser.userId}`, {
            limit: 20,
            windowMs: 60 * 1000,
        });
        return this.supportService.uploadImage(authUser, this.supportService.requireImage(file, 5 * 1024 * 1024), request?.query?.ticketId?.toString().trim() || undefined);
    }
    async createTicket(request, authUser, body) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(authUser.userId, request?.ip?.toString() ?? 'create'), {
            limit: 8,
            windowMs: 60 * 1000,
        });
        return this.supportService.createTicket(authUser, {
            name: body.name,
            subject: body.subject,
            text: body.text,
            imageUrl: body.imageUrl ?? body.image_url,
        });
    }
    async createBlockAppeal(request, authUser, body) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(authUser.userId, request?.ip?.toString() ?? 'block-appeal'), {
            limit: 4,
            windowMs: 60 * 1000,
        });
        return this.supportService.createBlockAppeal(authUser, {
            text: body.text,
            imageUrl: body.imageUrl ?? body.image_url,
        });
    }
    getTicket(authUser, ticketId) {
        return this.supportService.getTicketForUser(authUser, ticketId);
    }
    async sendMessage(request, authUser, ticketId, body) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(authUser.userId, request?.ip?.toString() ?? ticketId), {
            limit: 12,
            windowMs: 60 * 1000,
        });
        return this.supportService.sendMessageAsUser(authUser, ticketId, body.text, body.imageUrl ?? body.image_url);
    }
    closeTicket(authUser, ticketId) {
        return this.supportService.closeTicketForUser(authUser, ticketId);
    }
};
exports.SupportController = SupportController;
__decorate([
    (0, common_1.Get)('tickets'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], SupportController.prototype, "listTickets", null);
__decorate([
    (0, common_1.Post)('images'),
    (0, common_1.UseInterceptors)(memoryImageUpload),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Req)()),
    __param(2, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, Object]),
    __metadata("design:returntype", Promise)
], SupportController.prototype, "uploadImage", null);
__decorate([
    (0, common_1.Post)('tickets'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, create_support_ticket_dto_1.CreateSupportTicketDto]),
    __metadata("design:returntype", Promise)
], SupportController.prototype, "createTicket", null);
__decorate([
    (0, common_1.Post)('block-appeals'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, create_support_ticket_dto_1.CreateSupportTicketDto]),
    __metadata("design:returntype", Promise)
], SupportController.prototype, "createBlockAppeal", null);
__decorate([
    (0, common_1.Get)('tickets/:id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], SupportController.prototype, "getTicket", null);
__decorate([
    (0, common_1.Post)('tickets/:id/messages'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(3, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, String, send_support_message_dto_1.SendSupportMessageDto]),
    __metadata("design:returntype", Promise)
], SupportController.prototype, "sendMessage", null);
__decorate([
    (0, common_1.Patch)('tickets/:id/close'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], SupportController.prototype, "closeTicket", null);
exports.SupportController = SupportController = __decorate([
    (0, common_1.Controller)('support'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [support_service_1.SupportService,
        rate_limit_service_1.RateLimitService])
], SupportController);
let AdminSupportController = class AdminSupportController {
    constructor(supportService, rateLimitService) {
        this.supportService = supportService;
        this.rateLimitService = rateLimitService;
    }
    listTickets(query) {
        return this.supportService.listTickets(query);
    }
    getTicket(ticketId) {
        return this.supportService.getTicketForAdmin(ticketId);
    }
    async sendMessage(ticketId, body) {
        await this.rateLimitService.consumeOrThrow(`support:admin:${ticketId}`, {
            limit: 20,
            windowMs: 60 * 1000,
        });
        return this.supportService.sendMessageAsAdmin(ticketId, body.text, body.imageUrl ?? body.image_url);
    }
    contactUser(body) {
        return this.supportService.openTicketForAdminContact({
            userId: body.user_id ?? body.userId,
            name: body.name,
            subject: body.subject,
            text: body.text,
            idempotencyKey: body.idempotencyKey,
        });
    }
    closeTicket(ticketId) {
        return this.supportService.closeTicketForAdmin(ticketId);
    }
};
exports.AdminSupportController = AdminSupportController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [list_admin_support_tickets_dto_1.ListAdminSupportTicketsDto]),
    __metadata("design:returntype", void 0)
], AdminSupportController.prototype, "listTickets", null);
__decorate([
    (0, common_1.Get)(':id'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], AdminSupportController.prototype, "getTicket", null);
__decorate([
    (0, common_1.Post)(':id/messages'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, send_support_message_dto_1.SendSupportMessageDto]),
    __metadata("design:returntype", Promise)
], AdminSupportController.prototype, "sendMessage", null);
__decorate([
    (0, common_1.Post)('contact-user'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AdminSupportController.prototype, "contactUser", null);
__decorate([
    (0, common_1.Patch)(':id/close'),
    __param(0, (0, common_1.Param)('id', new common_1.ParseUUIDPipe())),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], AdminSupportController.prototype, "closeTicket", null);
exports.AdminSupportController = AdminSupportController = __decorate([
    (0, common_1.Controller)('admin/support'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:paramtypes", [support_service_1.SupportService,
        rate_limit_service_1.RateLimitService])
], AdminSupportController);
//# sourceMappingURL=support.controller.js.map