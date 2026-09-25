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
exports.PasswordlessController = void 0;
const common_1 = require("@nestjs/common");
const crypto_1 = require("crypto");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const passwordless_dto_1 = require("./dto/passwordless.dto");
const passwordless_service_1 = require("./passwordless.service");
let PasswordlessController = class PasswordlessController {
    constructor(passwordless, rateLimit) {
        this.passwordless = passwordless;
        this.rateLimit = rateLimit;
    }
    start(request, response, dto) {
        return this.run('start', request, response, () => this.passwordless.start(dto.phone, {
            ip: request.ip,
            deviceId: request.headers?.['x-device-id'] || request.headers?.['x-client-device-id'],
            userAgent: request.headers?.['user-agent'],
        }, dto));
    }
    check(request, response, dto) {
        return this.run('check', request, response, () => this.passwordless.check(dto.challenge));
    }
    complete(request, response, dto) {
        return this.run('complete', request, response, () => this.passwordless.complete(dto));
    }
    async run(action, request, response, work) {
        response.setHeader('Cache-Control', 'no-store');
        try {
            const signals = [request.ip || 'unknown', request.headers?.['x-device-id'] || request.headers?.['x-client-device-id']];
            for (const [index, signal] of signals.entries()) {
                if (!signal)
                    continue;
                const key = (0, crypto_1.createHash)('sha256').update(String(signal)).digest('hex');
                await this.rateLimit.consumeOrThrow(`passwordless:${action}:source:${index}:${key}`, {
                    limit: action === 'check' ? 60 : 10, windowMs: 60_000,
                });
            }
            const result = await work();
            if (result && typeof result === 'object' && 'retryAfterSeconds' in result &&
                typeof result.retryAfterSeconds === 'number') {
                response.setHeader('Retry-After', String(result.retryAfterSeconds));
            }
            return result;
        }
        catch (error) {
            if (error instanceof common_1.HttpException && error.getStatus() === 429)
                response.setHeader('Retry-After', '60');
            throw error;
        }
    }
};
exports.PasswordlessController = PasswordlessController;
__decorate([
    (0, common_1.Post)('start'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Res)({ passthrough: true })),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, passwordless_dto_1.PasswordlessStartDto]),
    __metadata("design:returntype", void 0)
], PasswordlessController.prototype, "start", null);
__decorate([
    (0, common_1.Post)('check'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Res)({ passthrough: true })),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, passwordless_dto_1.PasswordlessCheckDto]),
    __metadata("design:returntype", void 0)
], PasswordlessController.prototype, "check", null);
__decorate([
    (0, common_1.Post)('complete'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Res)({ passthrough: true })),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, passwordless_dto_1.PasswordlessCompleteDto]),
    __metadata("design:returntype", void 0)
], PasswordlessController.prototype, "complete", null);
exports.PasswordlessController = PasswordlessController = __decorate([
    (0, common_1.Controller)('auth/passwordless'),
    __metadata("design:paramtypes", [passwordless_service_1.PasswordlessService, rate_limit_service_1.RateLimitService])
], PasswordlessController);
//# sourceMappingURL=passwordless.controller.js.map