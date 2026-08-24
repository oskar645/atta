import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FeedAdsService } from './feed-ads.service';

@Controller()
export class FeedAdsController {
  constructor(private readonly feedAdsService: FeedAdsService) {}

  @Get('feed-ads')
  list(@Query('placement') placement?: string) {
    return this.feedAdsService.listAll(placement);
  }

  @Get('feed-ads/active')
  active(
    @Query('placement') placement?: string,
    @Query('after_id') afterId?: string,
  ) {
    return this.feedAdsService.getActive(placement, afterId);
  }

  @Post('feed-ads/:id/impression')
  impression(@Req() request: any, @Param('id') id: string) {
    return this.feedAdsService.recordImpression(id, this.counterSource(request));
  }

  @Post('feed-ads/:id/click')
  click(@Req() request: any, @Param('id') id: string) {
    return this.feedAdsService.recordClick(id, this.counterSource(request));
  }

  private counterSource(request: any) {
    const forwarded = `${request?.headers?.['x-forwarded-for'] ?? ''}`.trim();
    return {
      ip:
        `${request?.ip ?? ''}`.trim() ||
        forwarded.split(',')[0]?.trim() ||
        'unknown',
      userAgent: `${request?.headers?.['user-agent'] ?? ''}`.trim(),
    };
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Get('admin/feed-ads')
  adminList(@Query('placement') placement?: string) {
    return this.feedAdsService.listAll(placement);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/feed-ads')
  create(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: Record<string, unknown>,
  ) {
    return this.feedAdsService.create(authUser, body);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Patch('admin/feed-ads/:id')
  update(
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.feedAdsService.update(id, body);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/feed-ads/:id/activate')
  activate(@Param('id') id: string) {
    return this.feedAdsService.activate(id);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Post('admin/feed-ads/:id/deactivate')
  deactivate(@Param('id') id: string) {
    return this.feedAdsService.deactivate(id);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Delete('admin/feed-ads/:id')
  remove(@Param('id') id: string) {
    return this.feedAdsService.remove(id);
  }
}
