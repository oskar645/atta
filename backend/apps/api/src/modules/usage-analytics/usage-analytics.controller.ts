import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { OptionalJwtAuthGuard } from '../auth/optional-jwt-auth.guard';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { UsageAnalyticsService } from './usage-analytics.service';

export class GuestActivityDto { @IsUUID('4') guestId!: string; }
export class ListingOpenDto {
  @IsUUID('4') eventId!: string;
  @IsUUID() listingId!: string;
}
@Controller()
export class UsageAnalyticsController {
  constructor(private readonly analytics: UsageAnalyticsService, private readonly limits: RateLimitService) {}

  private limit(request: { ip?: string }) {
    // IP is used only for abuse throttling, never stored as analytics identity.
    return this.limits.consumeOrThrow(`analytics:${request.ip ?? 'unknown'}`, { limit: 240, windowMs: 60000 });
  }
  @Post('analytics/guest-activity')
  @UseGuards(OptionalJwtAuthGuard)
  async guest(@Body() dto: GuestActivityDto, @CurrentUser() user: AuthenticatedUser | undefined, @Req() request: { ip?: string }) {
    await this.limit(request);
    return this.analytics.guest(dto.guestId, user?.userId);
  }
  @Post('analytics/listing-open')
  @UseGuards(OptionalJwtAuthGuard)
  async open(@Body() dto: ListingOpenDto, @CurrentUser() user: AuthenticatedUser | undefined, @Req() request: { ip?: string }) {
    await this.limit(request);
    return this.analytics.listingOpen(dto.eventId, dto.listingId, user?.userId);
  }
  @Get('admin/dashboard/usage')
  @UseGuards(JwtAuthGuard, AdminGuard)
  dashboard() { return this.analytics.dashboard(); }
}
