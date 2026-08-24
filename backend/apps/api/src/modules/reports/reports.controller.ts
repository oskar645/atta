import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChatsGateway } from '../chats/chats.gateway';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { CreateReportDto } from './dto/create-report.dto';
import { ModerateReportDto } from './dto/moderate-report.dto';
import { ListAdminReportsDto } from './dto/list-admin-reports.dto';
import { ReportsService } from './reports.service';

@Controller('reports')
@UseGuards(JwtAuthGuard)
export class ReportsController {
  constructor(
    private readonly reportsService: ReportsService,
    private readonly chatsGateway: ChatsGateway,
    private readonly rateLimitService: RateLimitService,
  ) {}

  @Post()
  async create(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: CreateReportDto,
  ) {
    await this.rateLimitService.consumeOrThrow(
      `reports:${authUser.userId}:${request?.ip?.toString() ?? 'unknown'}`,
      {
        limit: 10,
        windowMs: 60 * 1000,
      },
    );
    return this.reportsService.create(authUser, body).then((result) => {
      const notifications = result['admin_notifications'];
      if (Array.isArray(notifications)) {
        for (const item of notifications) {
          if (!item || typeof item !== 'object') {
            continue;
          }
          const notification = item as Record<string, unknown>;
          const userId = `${notification['user_id'] ?? ''}`.trim();
          if (userId.length === 0) {
            continue;
          }
          this.chatsGateway.emitNotificationNew(notification, userId);
        }
      }
      return result;
    });
  }
}

@Controller('admin/reports')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get()
  list(@Query() query: ListAdminReportsDto) {
    return this.reportsService.listForAdmin(query);
  }

  @Patch(':id/resolve')
  resolve(
    @Param('id', new ParseUUIDPipe()) reportId: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: ModerateReportDto,
  ) {
    return this.reportsService.resolve(reportId, authUser, body.comment);
  }

  @Patch(':id/reject')
  reject(
    @Param('id', new ParseUUIDPipe()) reportId: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: ModerateReportDto,
  ) {
    return this.reportsService.reject(reportId, authUser, body.comment);
  }

  @Patch(':id/reopen')
  reopen(
    @Param('id', new ParseUUIDPipe()) reportId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.reportsService.reopen(reportId, authUser);
  }

  @Delete(':id')
  hide(
    @Param('id', new ParseUUIDPipe()) reportId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.reportsService.hide(reportId, authUser);
  }
}
