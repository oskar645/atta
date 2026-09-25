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
exports.PasswordlessCompleteDto = exports.PasswordlessCheckDto = exports.PasswordlessStartDto = void 0;
const class_validator_1 = require("class-validator");
const legal_document_version_1 = require("../legal-document-version");
class PasswordlessStartDto {
}
exports.PasswordlessStartDto = PasswordlessStartDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.Length)(1, 40),
    __metadata("design:type", String)
], PasswordlessStartDto.prototype, "phone", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.MaxLength)(200),
    __metadata("design:type", String)
], PasswordlessStartDto.prototype, "referralCode", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.MaxLength)(200),
    __metadata("design:type", String)
], PasswordlessStartDto.prototype, "referralId", void 0);
class PasswordlessCheckDto {
}
exports.PasswordlessCheckDto = PasswordlessCheckDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.Length)(80, 80),
    __metadata("design:type", String)
], PasswordlessCheckDto.prototype, "challenge", void 0);
class PasswordlessCompleteDto {
}
exports.PasswordlessCompleteDto = PasswordlessCompleteDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.Length)(80, 80),
    __metadata("design:type", String)
], PasswordlessCompleteDto.prototype, "registrationToken", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.Length)(1, 100),
    __metadata("design:type", String)
], PasswordlessCompleteDto.prototype, "displayName", void 0);
__decorate([
    (0, class_validator_1.Equals)(true),
    __metadata("design:type", Boolean)
], PasswordlessCompleteDto.prototype, "acceptedLegal", void 0);
__decorate([
    (0, class_validator_1.Equals)(true),
    __metadata("design:type", Boolean)
], PasswordlessCompleteDto.prototype, "acceptedPersonalData", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsBoolean)(),
    __metadata("design:type", Boolean)
], PasswordlessCompleteDto.prototype, "acceptedMarketing", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsIn)(['IOS', 'ANDROID', 'WEB']),
    __metadata("design:type", String)
], PasswordlessCompleteDto.prototype, "platform", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.MaxLength)(30),
    (0, class_validator_1.Equals)(legal_document_version_1.LEGAL_DOCUMENT_VERSION),
    __metadata("design:type", String)
], PasswordlessCompleteDto.prototype, "legalDocumentVersion", void 0);
//# sourceMappingURL=passwordless.dto.js.map