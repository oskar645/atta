import { Body, Controller, Delete, Get, Param, Patch, Query, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminService } from './admin.service';
import { ListAdminBonusAnalyticsDto } from './dto/list-admin-bonus-analytics.dto';
import { ListAdminListingsDto } from './dto/list-admin-listings.dto';
import { ListAdminPromotionsDto } from './dto/list-admin-promotions.dto';
import { ListAdminWalletTransactionsDto } from './dto/list-admin-wallet-transactions.dto';
import { ModerateListingDto } from './dto/moderate-listing.dto';
import { ArchiveListingDto } from '../listings/dto/archive-listing.dto';

@Controller('admin')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('dashboard/stats')
  getDashboardStats() {
    return this.adminService.getDashboardStats();
  }

  @Get('users')
  listUsers() {
    return this.adminService.listUsers();
  }

  @Get('users/:id')
  getUserById(@Param('id') id: string) {
    return this.adminService.getUserById(id);
  }

  @Delete('users/:id')
  deleteUser(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.adminService.deleteUser(id, authUser);
  }

  @Get('listings/moderation')
  getModerationQueue(@Query() query: ListAdminListingsDto) {
    return this.adminService.getModerationQueue(query.status ?? 'pending');
  }

  @Get('listings')
  getListingsAlias(@Query() query: ListAdminListingsDto) {
    return this.adminService.listListings(query.status);
  }

  @Get('promotions')
  listPromotions(@Query() query: ListAdminPromotionsDto) {
    return this.adminService.listPromotions(query);
  }

  @Get('promotions/summary')
  getPromotionsSummary() {
    return this.adminService.getPromotionsSummary();
  }

  @Patch('promotions/:id/cancel')
  cancelPromotion(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.adminService.cancelPromotion(id, authUser);
  }

  @Get('wallets')
  listWallets() {
    return this.adminService.listWallets();
  }

  @Get('wallet-transactions')
  listWalletTransactions(@Query() query: ListAdminWalletTransactionsDto) {
    return this.adminService.listWalletTransactions(query);
  }

  @Get('analytics/bonuses')
  getBonusAnalytics(@Query() query: ListAdminBonusAnalyticsDto) {
    return this.adminService.getBonusAnalytics(query);
  }

  @Patch('listings/:id/approve')
  approveListing(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.adminService.approveListing(id, authUser);
  }

  @Patch('listings/:id/reject')
  rejectListing(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: ModerateListingDto,
  ) {
    return this.adminService.rejectListing(id, authUser, {
      reason: dto.reason,
      moderationNote: dto.moderation_note,
    });
  }

  @Patch('listings/:id/archive')
  archiveListing(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: ArchiveListingDto,
  ) {
    return this.adminService.archiveListing(id, authUser, dto);
  }

  @Delete('listings/:id')
  deleteListing(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: ModerateListingDto,
  ) {
    return this.adminService.deleteListing(id, authUser, {
      reason: dto.reason,
      moderationNote: dto.moderation_note,
    });
  }

  @Delete('reviews/:id')
  deleteReview(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
  ) {
    return this.adminService.deleteReview(id, authUser);
  }

  @Get('reports')
  getReportsPlaceholder() {
    return this.adminService.getReportsPlaceholder();
  }

  @Get('support')
  getSupportAlias() {
    return this.adminService.getSupportTicketsPlaceholder();
  }

  @Get('support/tickets')
  getSupportTicketsPlaceholder() {
    return this.adminService.getSupportTicketsPlaceholder();
  }
}
