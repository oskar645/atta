import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Req, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { CreateReportDto } from './dto/create-report.dto';
import { ModerateReportDto } from './dto/moderate-report.dto';
import { ReportsService } from './reports.service';

@Controller('reports')
@UseGuards(JwtAuthGuard)
export class ReportsController {
  constructor(
    private readonly reportsService: ReportsService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  @Post()
  create(
    @Req() request: any,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: CreateReportDto,
  ) {
    this.rateLimitService.consumeOrThrow(
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
  list() {
    return this.reportsService.listForAdmin();
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
}
