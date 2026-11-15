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
    // Kept in the constructor for backward-compatible module wiring. Realtime
    // delivery is owned by NotificationsService and must not be emitted twice.
    private readonly _chatsGateway: ChatsGateway,
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
    return this.reportsService.create(authUser, body);
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
    return this.reportsService.resolve(
      reportId,
      authUser,
      body.comment,
      body.decision,
    );
  }

  @Patch(':id/reject')
  reject(
    @Param('id', new ParseUUIDPipe()) reportId: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: ModerateReportDto,
  ) {
    return this.reportsService.reject(
      reportId,
      authUser,
      body.comment,
      body.decision,
    );
  }

  @Patch(':id/start')
  startReview(
    @Param('id', new ParseUUIDPipe()) reportId: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.reportsService.startReview(reportId, authUser);
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
