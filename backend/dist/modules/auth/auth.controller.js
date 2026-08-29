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
exports.AuthController = void 0;
const common_1 = require("@nestjs/common");
const auth_service_1 = require("./auth.service");
const app_visits_service_1 = require("../app-visits/app-visits.service");
const current_user_decorator_1 = require("./current-user.decorator");
const login_dto_1 = require("./dto/login.dto");
const login_phone_dto_1 = require("./dto/login-phone.dto");
const logout_dto_1 = require("./dto/logout.dto");
const refresh_token_dto_1 = require("./dto/refresh-token.dto");
const reset_password_phone_dto_1 = require("./dto/reset-password-phone.dto");
const signup_dto_1 = require("./dto/signup.dto");
const signup_phone_dto_1 = require("./dto/signup-phone.dto");
const jwt_auth_guard_1 = require("./jwt-auth.guard");
const rate_limit_service_1 = require("../rate-limit/rate-limit.service");
const restore_credentials_service_1 = require("./restore-credentials.service");
const restore_credentials_dto_1 = require("./dto/restore-credentials.dto");
let AuthController = class AuthController {
    constructor(authService, appVisitsService, rateLimitService, restoreCredentialsService) {
        this.authService = authService;
        this.appVisitsService = appVisitsService;
        this.rateLimitService = rateLimitService;
        this.restoreCredentialsService = restoreCredentialsService;
    }
    rateKey(request, action) {
        const forwarded = request?.headers?.['x-forwarded-for']?.toString() ?? '';
        const ip = request?.ip?.toString().trim() ||
            forwarded.split(',')[0]?.trim() ||
            'unknown';
        return `auth:${action}:${ip}`;
    }
    async signup(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'signup'), {
            limit: 6,
            windowMs: 60 * 1000,
        });
        return this.authService.signup(dto);
    }
    async login(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'login'), {
            limit: 8,
            windowMs: 60 * 1000,
        });
        return this.authService.login(dto);
    }
    async signupPhone(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'signup-phone'), {
            limit: 6,
            windowMs: 60 * 1000,
        });
        return this.authService.signupPhone(dto);
    }
    async recordReferralOpen(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'referrals-open'), {
            limit: 30,
            windowMs: 60 * 1000,
        });
        return this.authService.recordReferralAppOpen(dto);
    }
    async loginPhone(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'login-phone'), {
            limit: 8,
            windowMs: 60 * 1000,
        });
        return this.authService.loginPhone(dto);
    }
    async resetPasswordPhone(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'reset-password-phone'), {
            limit: 5,
            windowMs: 60 * 1000,
        });
        return this.authService.resetPasswordPhone(dto);
    }
    getMe(authUser) {
        return this.authService.getMe(authUser);
    }
    createRestoreCredentialRegistrationOptions(authUser) {
        return this.restoreCredentialsService.createRegistrationOptions(authUser);
    }
    verifyRestoreCredentialRegistration(authUser, dto) {
        return this.restoreCredentialsService.verifyRegistration(authUser, dto.response);
    }
    async createRestoreCredentialAuthenticationOptions(request) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'restore-credentials-authentication-options'), {
            limit: 10,
            windowMs: 60 * 1000,
        });
        return this.restoreCredentialsService.createAuthenticationOptions();
    }
    async verifyRestoreCredentialAuthentication(request, dto) {
        await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'restore-credentials-authenticate'), {
            limit: 8,
            windowMs: 60 * 1000,
        });
        return this.restoreCredentialsService.verifyAuthentication(dto.response);
    }
    revokeRestoreCredential(authUser, dto) {
        return this.restoreCredentialsService.revoke(authUser, dto.credentialId ?? dto.credential_id);
    }
    markAppOpened(authUser) {
        return this.appVisitsService.markAppOpened(authUser.userId);
    }
    refresh(dto) {
        return this.authService.refresh(dto);
    }
    logout(authUser, dto) {
        return this.authService.logout(authUser, dto);
    }
    revokeOtherSessions(authUser) {
        return this.authService.revokeOtherSessions(authUser);
    }
    revokeAllSessions(authUser) {
        return this.authService.revokeAllSessions(authUser);
    }
    deleteAccount(authUser) {
        return this.authService.deleteAccount(authUser);
    }
};
exports.AuthController = AuthController;
__decorate([
    (0, common_1.Post)('signup'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, signup_dto_1.SignupDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "signup", null);
__decorate([
    (0, common_1.Post)('login'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, login_dto_1.LoginDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "login", null);
__decorate([
    (0, common_1.Post)('signup-phone'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, signup_phone_dto_1.SignupPhoneDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "signupPhone", null);
__decorate([
    (0, common_1.Post)('referrals/open'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "recordReferralOpen", null);
__decorate([
    (0, common_1.Post)('login-phone'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, login_phone_dto_1.LoginPhoneDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "loginPhone", null);
__decorate([
    (0, common_1.Post)('reset-password-phone'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, reset_password_phone_dto_1.ResetPasswordPhoneDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "resetPasswordPhone", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Get)('me'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "getMe", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('restore-credentials/registration-options'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "createRestoreCredentialRegistrationOptions", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('restore-credentials/register'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, restore_credentials_dto_1.VerifyRestoreCredentialRegistrationDto]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "verifyRestoreCredentialRegistration", null);
__decorate([
    (0, common_1.Post)('restore-credentials/authentication-options'),
    __param(0, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "createRestoreCredentialAuthenticationOptions", null);
__decorate([
    (0, common_1.Post)('restore-credentials/authenticate'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, restore_credentials_dto_1.VerifyRestoreCredentialAuthenticationDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "verifyRestoreCredentialAuthentication", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('restore-credentials/revoke'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, restore_credentials_dto_1.RevokeRestoreCredentialDto]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "revokeRestoreCredential", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('app-open'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "markAppOpened", null);
__decorate([
    (0, common_1.Post)('refresh'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [refresh_token_dto_1.RefreshTokenDto]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "refresh", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('logout'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, logout_dto_1.LogoutDto]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "logout", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('sessions/revoke-others'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "revokeOtherSessions", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Post)('sessions/revoke-all'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "revokeAllSessions", null);
__decorate([
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard),
    (0, common_1.Delete)('account'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "deleteAccount", null);
exports.AuthController = AuthController = __decorate([
    (0, common_1.Controller)('auth'),
    __metadata("design:paramtypes", [auth_service_1.AuthService,
        app_visits_service_1.AppVisitsService,
        rate_limit_service_1.RateLimitService,
        restore_credentials_service_1.RestoreCredentialsService])
], AuthController);
//# sourceMappingURL=auth.controller.js.map