import { Body, Controller, Delete, Post, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateFileUploadDto } from './dto/create-file-upload.dto';
import { CreateUploadUrlDto } from './dto/create-upload-url.dto';
import { DeleteObjectDto } from './dto/delete-object.dto';
import { StorageService } from './storage.service';

@Controller('storage')
@UseGuards(JwtAuthGuard, AdminGuard)
export class StorageController {
  constructor(private readonly storageService: StorageService) {}

  @Post('upload-url')
  createUploadUrl(@Body() dto: CreateUploadUrlDto) {
    return this.storageService.createUploadUrl(dto);
  }

  @Post('listing-photo/upload')
  createListingPhotoUpload(@Body() dto: CreateFileUploadDto) {
    return this.storageService.createListingPhotoUpload(
      dto.fileName,
      dto.contentType,
    );
  }

  @Post('avatar/upload')
  createAvatarUpload(@Body() dto: CreateFileUploadDto) {
    return this.storageService.createAvatarUpload(dto.fileName, dto.contentType);
  }

  @Post('chat-image/upload')
  createChatImageUpload(@Body() dto: CreateFileUploadDto) {
    return this.storageService.createChatImageUpload(
      dto.fileName,
      dto.contentType,
    );
  }

  @Delete('object')
  deleteObject(@Body() dto: DeleteObjectDto) {
    return this.storageService.deleteObject(dto);
  }
}
