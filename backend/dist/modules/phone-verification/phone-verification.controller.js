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
exports.PhoneVerificationController = void 0;
const common_1 = require("@nestjs/common");
const check_phone_registration_dto_1 = require("./dto/check-phone-registration.dto");
const check_phone_verification_dto_1 = require("./dto/check-phone-verification.dto");
const start_phone_verification_dto_1 = require("./dto/start-phone-verification.dto");
const phone_verification_service_1 = require("./phone-verification.service");
let PhoneVerificationController = class PhoneVerificationController {
    constructor(phoneVerificationService) {
        this.phoneVerificationService = phoneVerificationService;
    }
    checkRegistration(dto) {
        return this.phoneVerificationService.checkRegistration(dto.phone);
    }
    start(dto) {
        return this.phoneVerificationService.startCallVerification(dto.phone, dto.purpose);
    }
    check(dto) {
        return this.phoneVerificationService.checkCallVerification(dto.phone, dto.verificationId ?? dto.checkId ?? '', dto.purpose);
    }
};
exports.PhoneVerificationController = PhoneVerificationController;
__decorate([
    (0, common_1.Post)('check-registration'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [check_phone_registration_dto_1.CheckPhoneRegistrationDto]),
    __metadata("design:returntype", void 0)
], PhoneVerificationController.prototype, "checkRegistration", null);
__decorate([
    (0, common_1.Post)('start'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [start_phone_verification_dto_1.StartPhoneVerificationDto]),
    __metadata("design:returntype", void 0)
], PhoneVerificationController.prototype, "start", null);
__decorate([
    (0, common_1.Post)('check'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [check_phone_verification_dto_1.CheckPhoneVerificationDto]),
    __metadata("design:returntype", void 0)
], PhoneVerificationController.prototype, "check", null);
exports.PhoneVerificationController = PhoneVerificationController = __decorate([
    (0, common_1.Controller)('auth/phone'),
    __metadata("design:paramtypes", [phone_verification_service_1.PhoneVerificationService])
], PhoneVerificationController);
//# sourceMappingURL=phone-verification.controller.js.map