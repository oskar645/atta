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
exports.EmailPasswordlessController = void 0;
const common_1 = require("@nestjs/common");
const email_passwordless_dto_1 = require("./dto/email-passwordless.dto");
const email_passwordless_service_1 = require("./email-passwordless.service");
let EmailPasswordlessController = class EmailPasswordlessController {
    constructor(emailPasswordless) {
        this.emailPasswordless = emailPasswordless;
    }
    start(body, request) {
        return this.emailPasswordless.start(body.email, this.source(request));
    }
    check(body, request) {
        return this.emailPasswordless.check(body.challengeId, body.code, this.source(request));
    }
    complete(body, request) {
        return this.emailPasswordless.complete(body, this.source(request));
    }
    source(request) {
        const forwarded = request?.headers?.['x-forwarded-for']?.toString().split(',')[0]?.trim() ??
            '';
        return {
            ip: request?.ip?.toString().trim() || forwarded || 'unknown',
            deviceId: request?.headers?.['x-device-id']?.toString().trim() || '',
        };
    }
};
exports.EmailPasswordlessController = EmailPasswordlessController;
__decorate([
    (0, common_1.Post)('start'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [email_passwordless_dto_1.StartEmailPasswordlessDto, Object]),
    __metadata("design:returntype", void 0)
], EmailPasswordlessController.prototype, "start", null);
__decorate([
    (0, common_1.Post)('check'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [email_passwordless_dto_1.CheckEmailPasswordlessDto, Object]),
    __metadata("design:returntype", void 0)
], EmailPasswordlessController.prototype, "check", null);
__decorate([
    (0, common_1.Post)('complete'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [email_passwordless_dto_1.CompleteEmailPasswordlessDto, Object]),
    __metadata("design:returntype", void 0)
], EmailPasswordlessController.prototype, "complete", null);
exports.EmailPasswordlessController = EmailPasswordlessController = __decorate([
    (0, common_1.Controller)('auth/email'),
    __metadata("design:paramtypes", [email_passwordless_service_1.EmailPasswordlessService])
], EmailPasswordlessController);
//# sourceMappingURL=email-passwordless.controller.js.map