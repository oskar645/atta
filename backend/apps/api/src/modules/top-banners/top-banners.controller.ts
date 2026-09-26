import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { AdminGuard } from '../auth/admin.guard';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { TopBannersService } from './top-banners.service';

@Controller()
export class TopBannersController {
  constructor(private readonly service: TopBannersService) {}

  @Get('top-banners/active')
  active(@Query('after_id') afterId?: string) { return this.service.active(afterId); }

  @Post('top-banners/:id/impression')
  impression(@Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.service.track(id, 'IMPRESSION', body['session_id']);
  }

  @Post('top-banners/:id/click')
  click(@Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.service.track(id, 'CLICK', body['session_id']);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Get('admin/top-banners')
  list() { return this.service.list(); }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/top-banners')
  create(@CurrentUser() user: AuthenticatedUser, @Body() body: Record<string, unknown>) {
    return this.service.create(user, body);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Patch('admin/top-banners/:id')
  update(@Param('id') id: string, @Body() body: Record<string, unknown>) { return this.service.update(id, body); }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/top-banners/:id/start')
  start(@Param('id') id: string) { return this.service.start(id); }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/top-banners/:id/stop')
  stop(@Param('id') id: string) { return this.service.stop(id); }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/top-banners/:id/extend')
  extend(@Param('id') id: string, @Body() body: Record<string, unknown>) { return this.service.extend(id, body); }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Get('admin/top-banners/:id/stats')
  stats(@Param('id') id: string) { return this.service.stats(id); }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Delete('admin/top-banners/:id')
  remove(@Param('id') id: string) { return this.service.remove(id); }
}
