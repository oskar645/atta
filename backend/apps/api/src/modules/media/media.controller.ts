import {
  BadRequestException,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Query,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  Res,
  Logger,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtService } from '@nestjs/jwt';

import { env } from '../../config/env';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthTokenPayload, AuthenticatedUser } from '../auth/auth.types';
import { AdminGuard } from '../auth/admin.guard';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChatsGateway } from '../chats/chats.gateway';
import { ChatsService } from '../chats/chats.service';
import { FeedAdsService } from '../feed-ads/feed-ads.service';
import { ListingsService } from '../listings/listings.service';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { UsersService } from '../users/users.service';

const memoryImageUpload = FileInterceptor('file', {
  storage: require('multer').memoryStorage(),
});

// TODO: Video upload / 30 sec limit will be migrated later.

@Controller('media')
export class MediaController {
  private readonly logger = new Logger(MediaController.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
    private readonly rateLimitService: RateLimitService,
    private readonly chatsGateway: ChatsGateway,
    private readonly chatsService: ChatsService,
    private readonly feedAdsService: FeedAdsService,
    private readonly listingsService: ListingsService,
    private readonly storageService: StorageService,
    private readonly usersService: UsersService,
  ) {}

  @UseGuards(JwtAuthGuard)
  @Post('avatar')
  @UseInterceptors(memoryImageUpload)
  uploadAvatar(
    @CurrentUser() authUser: AuthenticatedUser,
    @UploadedFile() file?: UploadedImageFile,
  ) {
    this.rateLimitService.consumeOrThrow(`media:avatar:${authUser.userId}`, {
      limit: 15,
      windowMs: 60 * 1000,
    });
    return this.usersService.uploadAvatar(
      authUser,
      this.requireImage(file, 2 * 1024 * 1024),
    );
  }

  @UseGuards(JwtAuthGuard)
  @Post('listings/:listingId/photos')
  @UseInterceptors(memoryImageUpload)
  uploadListingPhoto(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('listingId', new ParseUUIDPipe()) listingId: string,
    @Req() request: any,
    @UploadedFile() file?: UploadedImageFile,
  ) {
    this.rateLimitService.consumeOrThrow(`media:listing:${authUser.userId}`, {
      limit: 20,
      windowMs: 60 * 1000,
    });
    const rawSortOrder = request?.body?.sort_order ?? request?.body?.sortOrder;
    const parsedSortOrder =
      typeof rawSortOrder === 'string' && rawSortOrder.trim().length > 0
        ? Number(rawSortOrder)
        : typeof rawSortOrder === 'number'
          ? rawSortOrder
          : undefined;
    return this.listingsService.uploadPhoto(
      authUser,
      listingId,
      this.requireImage(file, 5 * 1024 * 1024),
      Number.isFinite(parsedSortOrder) ? parsedSortOrder : undefined,
    );
  }

  @UseGuards(JwtAuthGuard)
  @Delete('listings/:listingId/photos/:photoId')
  deleteListingPhoto(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('listingId', new ParseUUIDPipe()) listingId: string,
    @Param('photoId', new ParseUUIDPipe()) photoId: string,
  ) {
    return this.listingsService.deletePhoto(authUser, listingId, photoId);
  }

  @UseGuards(JwtAuthGuard)
  @Post('chats/:chatId/images')
  @UseInterceptors(memoryImageUpload)
  uploadChatImage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('chatId', new ParseUUIDPipe()) chatId: string,
    @UploadedFile() file?: UploadedImageFile,
  ) {
    this.rateLimitService.consumeOrThrow(`media:chat:${authUser.userId}`, {
      limit: 20,
      windowMs: 60 * 1000,
    });
    return this.chatsService.uploadImage(
      authUser,
      chatId,
      this.requireImage(file, 2 * 1024 * 1024),
    ).then((result) => {
      this.chatsGateway.emitOutgoingMessage(
        result.chat,
        result.recipientChat,
        result.message,
        result.recipientId,
        result.notification,
      );
      return result;
    });
  }

  @Get('chats/:mediaId')
  async getChatImage(
    @Param('mediaId') mediaId: string,
    @Query('token') token: string | undefined,
    @Req() request: any,
    @Res() response: any,
  ) {
    const authUser = await this.authenticateRequest(request, token);
    const access = await this.chatsService.getChatImageAccess(authUser, mediaId);
    const bytes = await this.storageService.readChatFile(
      access.key,
      access.bucket,
    );
    this.debugProxyHit(
      'chats',
      access.key,
      access.bucket ?? 's3',
      200,
    );
    response.setHeader('Content-Type', access.mimeType);
    response.setHeader('Cache-Control', 'private, max-age=300');
    response.send(bytes);
  }

  @Get('chats/file')
  async getChatImageByKey(
    @Query('key') key: string,
    @Query('token') token: string | undefined,
    @Req() request: any,
    @Res() response: any,
  ) {
    const authUser = await this.authenticateRequest(request, token);
    const access = await this.chatsService.getChatImageAccessByKey(authUser, key);
    const bytes = await this.storageService.readChatFile(
      access.key,
      access.bucket,
    );
    this.debugProxyHit(
      'chats',
      access.key,
      access.bucket ?? 's3',
      200,
    );
    response.setHeader('Content-Type', access.mimeType);
    response.setHeader('Cache-Control', 'private, max-age=300');
    response.send(bytes);
  }

  @Get('object')
  async getPublicObject(
    @Query('category') category: string,
    @Query('key') key: string,
    @Res() response: any,
  ) {
    const allowed = new Set([
      'avatars',
      'listings',
      'feed-ads',
      'support',
      'reports',
      'misc',
      'videos',
    ]);
    if (!allowed.has(category) || !key?.trim()) {
      throw new BadRequestException('Файл не найден');
    }
    const bytes = await this.storageService.readStoredFile(
      category as any,
      key,
      's3',
    );
    this.debugProxyHit(category, key, 's3', 200);
    const lowerKey = key.toLowerCase();
    const mimeType = lowerKey.endsWith('.png')
      ? 'image/png'
      : lowerKey.endsWith('.webp')
        ? 'image/webp'
        : lowerKey.endsWith('.heic')
          ? 'image/heic'
          : lowerKey.endsWith('.heif')
            ? 'image/heif'
            : lowerKey.endsWith('.mp4')
              ? 'video/mp4'
              : lowerKey.endsWith('.mov')
                ? 'video/quicktime'
                : lowerKey.endsWith('.webm')
                  ? 'video/webm'
                  : 'image/jpeg';
    response.setHeader('Content-Type', mimeType);
    response.setHeader('Cache-Control', 'public, max-age=300');
    response.send(bytes);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('feed-ads/:feedAdId/image')
  @UseInterceptors(memoryImageUpload)
  uploadFeedAdImage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('feedAdId', new ParseUUIDPipe()) feedAdId: string,
    @UploadedFile() file?: UploadedImageFile,
  ) {
    return this.feedAdsService.attachImage(
      authUser,
      feedAdId,
      this.requireImage(file, 5 * 1024 * 1024),
    );
  }

  @UseGuards(JwtAuthGuard)
  @Delete(':id')
  deleteMedia(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') id: string,
  ) {
    if (authUser.role !== 'admin') {
      throw new ForbiddenException('Generic media delete is admin-only for now');
    }
    return this.storageService.deleteMediaByEntityId(id);
  }

  private requireImage(
    file: UploadedImageFile | undefined,
    maxSizeBytes: number,
  ) {
    if (!file || !file.buffer || file.size === 0) {
      throw new BadRequestException('Изображение обязательно');
    }

    const mime = file.mimetype.trim().toLowerCase();
    const allowed = new Set([
      'image/jpeg',
      'image/png',
      'image/webp',
    ]);
    if (!allowed.has(mime)) {
      throw new BadRequestException('Поддерживаются JPG, PNG и WEBP');
    }
    const detectedMime = this.detectImageMime(file.buffer);
    if (!detectedMime || detectedMime !== mime) {
      throw new BadRequestException('Файл не является корректным изображением');
    }
    if (file.size > maxSizeBytes) {
      throw new BadRequestException('Файл слишком большой');
    }
    return file;
  }

  private debugProxyHit(
    category: string,
    key: string,
    provider: string,
    status: number,
  ) {
    if (env.NODE_ENV === 'production') {
      return;
    }
    this.logger.debug(
      `Media proxy status=${status} category=${category} provider=${provider} key=${key}`,
    );
  }

  private detectImageMime(buffer: Buffer) {
    if (buffer.length >= 3 &&
        buffer[0] === 0xff &&
        buffer[1] === 0xd8 &&
        buffer[2] === 0xff) {
      return 'image/jpeg';
    }
    if (buffer.length >= 8 &&
        buffer[0] === 0x89 &&
        buffer[1] === 0x50 &&
        buffer[2] === 0x4e &&
        buffer[3] === 0x47 &&
        buffer[4] === 0x0d &&
        buffer[5] === 0x0a &&
        buffer[6] === 0x1a &&
        buffer[7] === 0x0a) {
      return 'image/png';
    }
    if (buffer.length >= 12 &&
        buffer[0] === 0x52 &&
        buffer[1] === 0x49 &&
        buffer[2] === 0x46 &&
        buffer[3] === 0x46 &&
        buffer[8] === 0x57 &&
        buffer[9] === 0x45 &&
        buffer[10] === 0x42 &&
        buffer[11] === 0x50) {
      return 'image/webp';
    }
    return null;
  }

  private async authenticateRequest(
    request: any,
    queryToken?: string,
  ): Promise<AuthenticatedUser> {
    const header = request?.headers?.authorization;
    const bearerHeader =
      typeof header === 'string' && header.startsWith('Bearer ')
        ? header.slice('Bearer '.length).trim()
        : '';
    const token = queryToken?.trim() || bearerHeader;
    if (!token) {
      throw new ForbiddenException('Access token is required');
    }

    let payload: AuthTokenPayload;
    try {
      payload = await this.jwtService.verifyAsync<AuthTokenPayload>(token, {
        secret: env.JWT_ACCESS_SECRET,
      });
    } catch {
      throw new ForbiddenException('Access token is invalid or expired');
    }

    const session = await this.prisma.userSession.findFirst({
      where: {
        id: payload.sessionId,
        userId: payload.sub,
        revokedAt: null,
      },
      select: {
        id: true,
        userId: true,
        expiresAt: true,
      },
    });
    if (!session || session.expiresAt.getTime() <= Date.now()) {
      throw new ForbiddenException('Session is not active');
    }

    return {
      userId: session.userId,
      sessionId: session.id,
      role: payload.role,
      email: payload.email,
    };
  }
}
