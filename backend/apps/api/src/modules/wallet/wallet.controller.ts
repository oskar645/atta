import { Controller, Get, Post, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { WalletService } from './wallet.service';

@Controller('wallet')
@UseGuards(JwtAuthGuard)
export class WalletController {
  constructor(private readonly walletService: WalletService) {}

  @Get()
  getWallet(@CurrentUser() authUser: AuthenticatedUser) {
    return this.walletService.getWallet(authUser);
  }

  @Get('transactions')
  getTransactions(@CurrentUser() authUser: AuthenticatedUser) {
    return this.walletService.getTransactions(authUser);
  }

  @Post('accrue/check')
  checkAccrual(@CurrentUser() authUser: AuthenticatedUser) {
    return this.walletService.checkAccrual(authUser);
  }
}
