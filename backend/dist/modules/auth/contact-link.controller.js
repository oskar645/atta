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
exports.ContactLinkController = void 0;
const common_1 = require("@nestjs/common");
const contact_link_service_1 = require("./contact-link.service");
const current_user_decorator_1 = require("./current-user.decorator");
const link_phone_dto_1 = require("./dto/link-phone.dto");
const jwt_auth_guard_1 = require("./jwt-auth.guard");
let ContactLinkController = class ContactLinkController {
    constructor(contactLink) {
        this.contactLink = contactLink;
    }
    start(user, body, request) {
        return this.contactLink.startPhone(user, body.phone, {
            ip: request?.ip?.toString(),
            deviceId: request?.headers?.['x-device-id']?.toString(),
            userAgent: request?.headers?.['user-agent']?.toString(),
        });
    }
    complete(user, body) {
        return this.contactLink.completePhone(user, body.phone, body.verificationId);
    }
};
exports.ContactLinkController = ContactLinkController;
__decorate([
    (0, common_1.Post)('start'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, link_phone_dto_1.StartLinkPhoneDto, Object]),
    __metadata("design:returntype", void 0)
], ContactLinkController.prototype, "start", null);
__decorate([
    (0, common_1.Post)('complete'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, link_phone_dto_1.CompleteLinkPhoneDto]),
    __metadata("design:returntype", void 0)
], ContactLinkController.prototype, "complete", null);
exports.ContactLinkController = ContactLinkController = __decorate([
    (0, common_1.Controller)('auth/link-phone'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __metadata("design:paramtypes", [contact_link_service_1.ContactLinkService])
], ContactLinkController);
//# sourceMappingURL=contact-link.controller.js.map