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
exports.StorageController = void 0;
const common_1 = require("@nestjs/common");
const create_file_upload_dto_1 = require("./dto/create-file-upload.dto");
const create_upload_url_dto_1 = require("./dto/create-upload-url.dto");
const delete_object_dto_1 = require("./dto/delete-object.dto");
const storage_service_1 = require("./storage.service");
let StorageController = class StorageController {
    constructor(storageService) {
        this.storageService = storageService;
    }
    createUploadUrl(dto) {
        return this.storageService.createUploadUrl(dto);
    }
    createListingPhotoUpload(dto) {
        return this.storageService.createListingPhotoUpload(dto.fileName, dto.contentType);
    }
    createAvatarUpload(dto) {
        return this.storageService.createAvatarUpload(dto.fileName, dto.contentType);
    }
    createChatImageUpload(dto) {
        return this.storageService.createChatImageUpload(dto.fileName, dto.contentType);
    }
    deleteObject(dto) {
        return this.storageService.deleteObject(dto);
    }
};
exports.StorageController = StorageController;
__decorate([
    (0, common_1.Post)('upload-url'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_upload_url_dto_1.CreateUploadUrlDto]),
    __metadata("design:returntype", void 0)
], StorageController.prototype, "createUploadUrl", null);
__decorate([
    (0, common_1.Post)('listing-photo/upload'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_file_upload_dto_1.CreateFileUploadDto]),
    __metadata("design:returntype", void 0)
], StorageController.prototype, "createListingPhotoUpload", null);
__decorate([
    (0, common_1.Post)('avatar/upload'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_file_upload_dto_1.CreateFileUploadDto]),
    __metadata("design:returntype", void 0)
], StorageController.prototype, "createAvatarUpload", null);
__decorate([
    (0, common_1.Post)('chat-image/upload'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_file_upload_dto_1.CreateFileUploadDto]),
    __metadata("design:returntype", void 0)
], StorageController.prototype, "createChatImageUpload", null);
__decorate([
    (0, common_1.Delete)('object'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [delete_object_dto_1.DeleteObjectDto]),
    __metadata("design:returntype", void 0)
], StorageController.prototype, "deleteObject", null);
exports.StorageController = StorageController = __decorate([
    (0, common_1.Controller)('storage'),
    __metadata("design:paramtypes", [storage_service_1.StorageService])
], StorageController);
//# sourceMappingURL=storage.controller.js.map