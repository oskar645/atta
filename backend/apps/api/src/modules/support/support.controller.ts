import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { CreateSupportTicketDto } from './dto/create-support-ticket.dto';
import { ListAdminSupportTicketsDto } from './dto/list-admin-support-tickets.dto';
import { SendSupportMessageDto } from './dto/send-support-message.dto';
import { UpdateSupportMessageDto } from './dto/update-support-message.dto';
import { SupportService } from './support.service';
import { CreatePublicSupportTicketDto, PublicSupportMessageDto } from './dto/public-support.dto';
import { IMAGE_UPLOAD_LIMITS, memoryImageUploadOptions } from '../media/image-upload';

const memoryImageUpload = FileInterceptor('file', memoryImageUploadOptions(IMAGE_UPLOAD_LIMITS.support));

@Controller('support/public')
export class PublicSupportController {
  constructor(private readonly supportService: SupportService, private readonly rateLimitService: RateLimitService) {}

  @Post('tickets')
  async create(@Req() req: any, @Body() body: CreatePublicSupportTicketDto) {
    await this.rateLimitService.consumeOrThrow(`support:public:create:${req?.ip ?? 'unknown'}`, { limit: 3, windowMs: 60 * 60_000 });
    return this.supportService.createPublicAccessTicket(body);
  }

  @Get('tickets/:id')
  async get(@Req() req: any, @Param('id', new ParseUUIDPipe()) id: string) {
    const token = this.token(req);
    await this.rateLimitService.consumeOrThrow(`support:public:read:${id}:${req?.ip ?? 'unknown'}`, { limit: 60, windowMs: 60_000 });
    return this.supportService.getPublicTicket(id, token);
  }

  @Post('tickets/:id/messages')
  async send(@Req() req: any, @Param('id', new ParseUUIDPipe()) id: string, @Body() body: PublicSupportMessageDto) {
    const token = this.token(req);
    await this.rateLimitService.consumeOrThrow(`support:public:send:${id}:${req?.ip ?? 'unknown'}`, { limit: 8, windowMs: 60_000 });
    return this.supportService.sendPublicMessage(id, token, body.text);
  }

  private token(req: any) {
    return req?.headers?.['x-support-token']?.toString().trim() ?? '';
  }
}

@Controller('support')
@UseGuards(JwtAuthGuard)
export class SupportController {
  constructor(
    private readonly supportService: SupportService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  private rateKey(userId: string, ticketId: string) {
    return `support:${userId}:${ticketId}`;
  }

  @Get('tickets')
  listTickets(@CurrentUser() authUser: AuthenticatedUser) {
    return this.supportService.listMyTickets(authUser);
  }

  @Post('images')
  @UseInterceptors(memoryImageUpload)
  async uploadImage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Req() request: any,
    @UploadedFile() file?: UploadedImageFile,
  ) {
    await this.rateLimitService.consumeOrThrow(`support:image:${authUser.userId}`, {
      limit: 20,
      windowMs: 60 * 1000,
    });
    return this.supportService.uploadImage(
      authUser,
      this.supportService.requireImage(file, 5 * 1024 * 1024),
      request?.query?.ticketId?.toString().trim() || undefined,
    );
  }

  @Post('tickets')
  async createTicket(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: CreateSupportTicketDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      this.rateKey(authUser.userId, request?.ip?.toString() ?? 'create'),
      {
        limit: 8,
        windowMs: 60 * 1000,
      },
    );
    return this.supportService.createTicket(authUser, {
      name: body.name,
      subject: body.subject,
      text: body.text,
      imageUrl: body.imageUrl ?? body.image_url,
      idempotencyKey: body.idempotencyKey,
    });
  }

  @Post('block-appeals')
  async createBlockAppeal(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: CreateSupportTicketDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      this.rateKey(authUser.userId, request?.ip?.toString() ?? 'block-appeal'),
      {
        limit: 4,
        windowMs: 60 * 1000,
      },
    );
    return this.supportService.createBlockAppeal(authUser, {
      text: body.text,
      imageUrl: body.imageUrl ?? body.image_url,
    });
  }

  @Get('tickets/:id')
  getTicket(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
  ) {
    return this.supportService.getTicketForUser(authUser, ticketId);
  }

  @Post('tickets/:id/messages')
  async sendMessage(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Body() body: SendSupportMessageDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      this.rateKey(authUser.userId, request?.ip?.toString() ?? ticketId),
      {
        limit: 12,
        windowMs: 60 * 1000,
      },
    );
    return this.supportService.sendMessageAsUser(
      authUser,
      ticketId,
      body.text,
      body.imageUrl ?? body.image_url,
      body.idempotencyKey,
    );
  }

  @Patch('tickets/:id/messages/:messageId/read')
  markMessageRead(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Param('messageId', new ParseUUIDPipe()) messageId: string,
  ) {
    return this.supportService.markMessageReadByUser(authUser, ticketId, messageId);
  }

  @Patch('tickets/:id/close')
  closeTicket(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
  ) {
    return this.supportService.closeTicketForUser(authUser, ticketId);
  }
}

@Controller('admin/support')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminSupportController {
  constructor(
    private readonly supportService: SupportService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  @Get()
  listTickets(@Query() query: ListAdminSupportTicketsDto) {
    return this.supportService.listTickets(query);
  }

  @Get(':id')
  getTicket(@Param('id', new ParseUUIDPipe()) ticketId: string) {
    return this.supportService.getTicketForAdmin(ticketId);
  }

  @Patch(':id/read')
  markRead(@Param('id', new ParseUUIDPipe()) ticketId: string) {
    return this.supportService.markReadByAdmin(ticketId);
  }

  @Post(':id/messages')
  async sendMessage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Body() body: SendSupportMessageDto,
  ) {
    await this.rateLimitService.consumeOrThrow(`support:admin:${ticketId}`, {
      limit: 20,
      windowMs: 60 * 1000,
    });
    return this.supportService.sendMessageAsAdmin(
      authUser,
      ticketId,
      body.text,
      body.imageUrl ?? body.image_url,
      body.idempotencyKey,
    );
  }

  @Patch(':id/messages/:messageId')
  editMessage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Param('messageId', new ParseUUIDPipe()) messageId: string,
    @Body() body: UpdateSupportMessageDto,
  ) {
    return this.supportService.editMessageAsAdmin(
      authUser,
      ticketId,
      messageId,
      body.text,
    );
  }

  @Delete(':id/messages/:messageId')
  deleteMessage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Param('messageId', new ParseUUIDPipe()) messageId: string,
  ) {
    return this.supportService.deleteMessageAsAdmin(authUser, ticketId, messageId);
  }

  @Post('contact-user')
  contactUser(
    @Body()
    body: {
      user_id?: string;
      userId?: string;
      name?: string;
      subject?: string;
      text?: string;
      idempotencyKey?: string;
    },
  ) {
    return this.supportService.openTicketForAdminContact({
      userId: body.user_id ?? body.userId,
      name: body.name,
      subject: body.subject,
      text: body.text,
      idempotencyKey: body.idempotencyKey,
    });
  }

  @Patch(':id/close')
  closeTicket(@Param('id', new ParseUUIDPipe()) ticketId: string) {
    return this.supportService.closeTicketForAdmin(ticketId);
  }
}
