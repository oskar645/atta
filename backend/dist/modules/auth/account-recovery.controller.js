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
exports.AccountRecoveryController = exports.RecoveryEmailController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("./current-user.decorator");
const jwt_auth_guard_1 = require("./jwt-auth.guard");
const account_recovery_service_1 = require("./account-recovery.service");
const account_recovery_dto_1 = require("./dto/account-recovery.dto");
let RecoveryEmailController = class RecoveryEmailController {
    constructor(recovery) {
        this.recovery = recovery;
    }
    start(user, body, req) {
        return this.recovery.startRecoveryEmail(user.userId, body.email, this.source(req));
    }
    verify(user, body) {
        return this.recovery.verifyRecoveryEmail(user.userId, body.challengeId, body.code);
    }
    source(req) {
        return { ip: req?.ip?.toString(), deviceId: req?.headers?.['x-device-id']?.toString() };
    }
};
exports.RecoveryEmailController = RecoveryEmailController;
__decorate([
    (0, common_1.Post)('start'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, account_recovery_dto_1.StartRecoveryEmailDto, Object]),
    __metadata("design:returntype", void 0)
], RecoveryEmailController.prototype, "start", null);
__decorate([
    (0, common_1.Post)('verify'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, account_recovery_dto_1.VerifyEmailCodeDto]),
    __metadata("design:returntype", void 0)
], RecoveryEmailController.prototype, "verify", null);
exports.RecoveryEmailController = RecoveryEmailController = __decorate([
    (0, common_1.Controller)('auth/recovery-email'),
    __metadata("design:paramtypes", [account_recovery_service_1.AccountRecoveryService])
], RecoveryEmailController);
let AccountRecoveryController = class AccountRecoveryController {
    constructor(recovery) {
        this.recovery = recovery;
    }
    start(body, req) {
        return this.recovery.startAccountRecovery(body.email, this.source(req));
    }
    verifyEmail(body, req) {
        return this.recovery.verifyAccountRecoveryEmail(body.challengeId, body.code, this.source(req));
    }
    startPhone(body, req) {
        return this.recovery.startPhone(body.recoveryToken, body.phone, this.source(req));
    }
    completePhone(body) {
        return this.recovery.completePhone(body.recoveryToken, body.phone, body.verificationCheckId);
    }
    source(req) {
        return { ip: req?.ip?.toString(), deviceId: req?.headers?.['x-device-id']?.toString(), userAgent: req?.headers?.['user-agent']?.toString() };
    }
};
exports.AccountRecoveryController = AccountRecoveryController;
__decorate([
    (0, common_1.Post)('start'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [account_recovery_dto_1.StartRecoveryEmailDto, Object]),
    __metadata("design:returntype", void 0)
], AccountRecoveryController.prototype, "start", null);
__decorate([
    (0, common_1.Post)('verify-email'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [account_recovery_dto_1.VerifyEmailCodeDto, Object]),
    __metadata("design:returntype", void 0)
], AccountRecoveryController.prototype, "verifyEmail", null);
__decorate([
    (0, common_1.Post)('phone/start'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [account_recovery_dto_1.StartRecoveryPhoneDto, Object]),
    __metadata("design:returntype", void 0)
], AccountRecoveryController.prototype, "startPhone", null);
__decorate([
    (0, common_1.Post)('phone/complete'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [account_recovery_dto_1.CompleteRecoveryPhoneDto]),
    __metadata("design:returntype", void 0)
], AccountRecoveryController.prototype, "completePhone", null);
exports.AccountRecoveryController = AccountRecoveryController = __decorate([
    (0, common_1.Controller)('auth/account-recovery'),
    __metadata("design:paramtypes", [account_recovery_service_1.AccountRecoveryService])
], AccountRecoveryController);
//# sourceMappingURL=account-recovery.controller.js.map