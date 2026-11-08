import { Controller, Get, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminAppDownloadsService } from './admin-app-downloads.service';

@Controller('admin/dashboard/app-downloads')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminAppDownloadsController {
  constructor(private readonly appDownloads: AdminAppDownloadsService) {}

  @Get()
  getAppDownloads() {
    return this.appDownloads.getSnapshot();
  }
}
