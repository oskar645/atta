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
exports.AdminNotificationsController = exports.NotificationsController = void 0;
const common_1 = require("@nestjs/common");
const admin_guard_1 = require("../auth/admin.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const chats_gateway_1 = require("../chats/chats.gateway");
const notifications_service_1 = require("./notifications.service");
let NotificationsController = class NotificationsController {
    constructor(notificationsService) {
        this.notificationsService = notificationsService;
    }
    listInAppNotifications(authUser) {
        return this.notificationsService.listInAppNotifications(authUser);
    }
    markRead(authUser, notificationId) {
        return this.notificationsService.markRead(authUser, notificationId);
    }
    markAllRead(authUser) {
        return this.notificationsService.markAllRead(authUser);
    }
    markAllSeen(authUser) {
        return this.notificationsService.markAllSeen(authUser);
    }
    deleteNotification(authUser, notificationId) {
        return this.notificationsService.deleteNotification(authUser, notificationId);
    }
    sendPushPlaceholder() {
        return this.notificationsService.sendPushPlaceholder();
    }
};
exports.NotificationsController = NotificationsController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "listInAppNotifications", null);
__decorate([
    (0, common_1.Patch)(':id/read'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "markRead", null);
__decorate([
    (0, common_1.Patch)('read-all'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "markAllRead", null);
__decorate([
    (0, common_1.Patch)('seen-all'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "markAllSeen", null);
__decorate([
    (0, common_1.Delete)(':id'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "deleteNotification", null);
__decorate([
    (0, common_1.Post)('push/test'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "sendPushPlaceholder", null);
exports.NotificationsController = NotificationsController = __decorate([
    (0, common_1.Controller)('notifications'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [notifications_service_1.NotificationsService])
], NotificationsController);
let AdminNotificationsController = class AdminNotificationsController {
    constructor(notificationsService, chatsGateway) {
        this.notificationsService = notificationsService;
        this.chatsGateway = chatsGateway;
    }
    async sendToUser(body) {
        const result = await this.notificationsService.sendToUser({
            userId: body.user_id ?? body.userId,
            title: body.title,
            body: body.body,
            type: body.type,
        });
        this.chatsGateway.emitNotificationNew(result.item, (result.item.user_id ?? '').toString());
        return result;
    }
    async sendToAll(body) {
        const result = await this.notificationsService.sendToAll(body);
        this.chatsGateway.emitNotificationNew(result.item);
        return result;
    }
};
exports.AdminNotificationsController = AdminNotificationsController;
__decorate([
    (0, common_1.Post)('send-user'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AdminNotificationsController.prototype, "sendToUser", null);
__decorate([
    (0, common_1.Post)('send-all'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AdminNotificationsController.prototype, "sendToAll", null);
exports.AdminNotificationsController = AdminNotificationsController = __decorate([
    (0, common_1.Controller)('admin/notifications'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, admin_guard_1.AdminGuard),
    __metadata("design:paramtypes", [notifications_service_1.NotificationsService,
        chats_gateway_1.ChatsGateway])
], AdminNotificationsController);
//# sourceMappingURL=notifications.controller.js.map