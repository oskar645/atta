import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
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
import { SendSupportMessageDto } from './dto/send-support-message.dto';
import { SupportService } from './support.service';

const memoryImageUpload = FileInterceptor('file', {
  storage: require('multer').memoryStorage(),
});

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
  uploadImage(
    @CurrentUser() authUser: AuthenticatedUser,
    @Req() request: any,
    @UploadedFile() file?: UploadedImageFile,
  ) {
    this.rateLimitService.consumeOrThrow(`support:image:${authUser.userId}`, {
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
  createTicket(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: CreateSupportTicketDto,
  ) {
    this.rateLimitService.consumeOrThrow(
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
  sendMessage(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Body() body: SendSupportMessageDto,
  ) {
    this.rateLimitService.consumeOrThrow(
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
    );
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
  listTickets() {
    return this.supportService.listTickets();
  }

  @Get(':id')
  getTicket(@Param('id', new ParseUUIDPipe()) ticketId: string) {
    return this.supportService.getTicketForAdmin(ticketId);
  }

  @Post(':id/messages')
  sendMessage(
    @Param('id', new ParseUUIDPipe()) ticketId: string,
    @Body() body: SendSupportMessageDto,
  ) {
    this.rateLimitService.consumeOrThrow(`support:admin:${ticketId}`, {
      limit: 20,
      windowMs: 60 * 1000,
    });
    return this.supportService.sendMessageAsAdmin(
      ticketId,
      body.text,
      body.imageUrl ?? body.image_url,
    );
  }

  @Patch(':id/close')
  closeTicket(@Param('id', new ParseUUIDPipe()) ticketId: string) {
    return this.supportService.closeTicketForAdmin(ticketId);
  }
}
