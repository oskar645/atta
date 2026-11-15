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
exports.CompleteEmailPasswordlessDto = exports.CheckEmailPasswordlessDto = exports.StartEmailPasswordlessDto = void 0;
const class_validator_1 = require("class-validator");
class StartEmailPasswordlessDto {
}
exports.StartEmailPasswordlessDto = StartEmailPasswordlessDto;
__decorate([
    (0, class_validator_1.IsEmail)(),
    (0, class_validator_1.MaxLength)(320),
    __metadata("design:type", String)
], StartEmailPasswordlessDto.prototype, "email", void 0);
class CheckEmailPasswordlessDto {
}
exports.CheckEmailPasswordlessDto = CheckEmailPasswordlessDto;
__decorate([
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], CheckEmailPasswordlessDto.prototype, "challengeId", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.Matches)(/^\d{6}$/),
    __metadata("design:type", String)
], CheckEmailPasswordlessDto.prototype, "code", void 0);
class CompleteEmailPasswordlessDto {
}
exports.CompleteEmailPasswordlessDto = CompleteEmailPasswordlessDto;
__decorate([
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], CompleteEmailPasswordlessDto.prototype, "registrationToken", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.Length)(1, 100),
    __metadata("design:type", String)
], CompleteEmailPasswordlessDto.prototype, "displayName", void 0);
__decorate([
    (0, class_validator_1.IsBoolean)(),
    __metadata("design:type", Boolean)
], CompleteEmailPasswordlessDto.prototype, "acceptedLegal", void 0);
__decorate([
    (0, class_validator_1.IsBoolean)(),
    __metadata("design:type", Boolean)
], CompleteEmailPasswordlessDto.prototype, "acceptedPersonalData", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsBoolean)(),
    __metadata("design:type", Boolean)
], CompleteEmailPasswordlessDto.prototype, "acceptedMarketing", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], CompleteEmailPasswordlessDto.prototype, "platform", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], CompleteEmailPasswordlessDto.prototype, "legalDocumentVersion", void 0);
//# sourceMappingURL=email-passwordless.dto.js.map