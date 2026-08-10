import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';

import { AdminGuard } from '../auth/admin.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminService } from './admin.service';
import { ListAdminBonusAnalyticsDto } from './dto/list-admin-bonus-analytics.dto';
import { ListAdminListingsDto } from './dto/list-admin-listings.dto';
import { ListAdminPointsPurchasesDto } from './dto/list-admin-points-purchases.dto';
import { ListAdminPromotionsDto } from './dto/list-admin-promotions.dto';
import { ListAdminBlocksDto } from './dto/list-admin-blocks.dto';
import { ListAdminWalletTransactionsDto } from './dto/list-admin-wallet-transactions.dto';
import { ListAdminUsersDto } from './dto/list-admin-users.dto';
import { ModerateListingDto } from './dto/moderate-listing.dto';
import { ArchiveListingDto } from '../listings/dto/archive-listing.dto';
import { BlockUserDto, UnblockUserDto, UpdateUserBlockDto } from './dto/block-user.dto';
import { SendAdminSupportMessageDto } from './dto/send-admin-support-message.dto';
import { SupportService } from '../support/support.service';

@Controller('admin')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly supportService: SupportService,
  ) {}

  @Get('dashboard/stats')
  getDashboardStats() {
    return this.adminService.getDashboardStats();
  }

  @Get('users')
  listUsers(@Query() query: ListAdminUsersDto) {
    return this.adminService.listUsers(query);
  }

  @Get('online-users')
  listOnlineUsers() {
    return this.adminService.listOnlineUsers();
  }

  @Get('today-visits')
  listTodayVisits() {
    return this.adminService.listTodayVisits();
  }

  @Get('users/:id')
  getUserById(@Param('id') id: string) {
    return this.adminService.getUserById(id);
  }

  @Post('users/:userId/support-message')
  sendSupportMessageToUser(
    @Param('userId', new ParseUUIDPipe()) userId: string,
    @Body() dto: SendAdminSupportMessageDto,
  ) {
    return this.supportService.openTicketForAdminContact({
      userId,
      text: dto.message,
      idempotencyKey: dto.idempotencyKey,
      subject: 'Сообщение от администрации',
    });
  }

  @Get('users/:userId/referrals')
  getUserReferrals(
    @Param('userId') userId: string,
    @Query() query: ListAdminBonusAnalyticsDto,
  ) {
    return this.adminService.getUserReferrals(userId, query);
  }

  @Post('users/:id/block')
  blockUser(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: BlockUserDto,
  ) {
    return this.adminService.blockUser(id, authUser, dto);
  }

  @Get('blocks')
  listBlocks(@Query() query: ListAdminBlocksDto) {
    return this.adminService.listBlocks(query);
  }

  @Post('blocks/:id/unblock')
  unblockUserBlock(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: UnblockUserDto,
  ) {
    return this.adminService.unblockUserBlock(id, authUser, dto);
  }

  @Patch('blocks/:id')
  updateUserBlock(
    @Param('id') id: string,
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: UpdateUserBlockDto,
  ) {
    return this.adminService.updateUserBlock(id, authUser, dto);
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
    return this.adminService.getModerationQueue(query);
  }

  @Get('listings')
  getListingsAlias(@Query() query: ListAdminListingsDto) {
    return this.adminService.listListings(query);
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
  listWallets(@Query() query: ListAdminUsersDto) {
    return this.adminService.listWallets(query);
  }

  @Get('wallet-transactions')
  listWalletTransactions(@Query() query: ListAdminWalletTransactionsDto) {
    return this.adminService.listWalletTransactions(query);
  }

  @Get('analytics/bonuses')
  getBonusAnalytics(@Query() query: ListAdminBonusAnalyticsDto) {
    return this.adminService.getBonusAnalytics(query);
  }

  @Get('payments/points-purchases/summary')
  getPointsPurchasesSummary(@Query() query: ListAdminPointsPurchasesDto) {
    return this.adminService.getPointsPurchasesSummary(query);
  }

  @Get('payments/points-purchases')
  listPointsPurchases(@Query() query: ListAdminPointsPurchasesDto) {
    return this.adminService.listPointsPurchases(query);
  }

  @Get('referrals/summary')
  getReferralsSummary(@Query() query: ListAdminBonusAnalyticsDto) {
    return this.adminService.getReferralSummary(query);
  }

  @Get('referrals')
  listReferrals(@Query() query: ListAdminBonusAnalyticsDto) {
    return this.adminService.listReferrals(query);
  }

  @Get('referrals/:id')
  getReferralById(@Param('id') id: string) {
    return this.adminService.getReferralById(id);
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
    return this.supportService.listTickets();
  }

  @Get('support/tickets')
  getSupportTicketsPlaceholder() {
    return this.supportService.listTickets();
  }
}
