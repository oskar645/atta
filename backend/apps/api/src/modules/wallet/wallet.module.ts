import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';

import { env } from '../../config/env';
import { WALLET_NOW_PROVIDER } from './wallet.constants';
import { WalletController } from './wallet.controller';
import { WalletService } from './wallet.service';

@Module({
  imports: [
    JwtModule.register({
      secret: env.JWT_ACCESS_SECRET,
    }),
  ],
  controllers: [WalletController],
  providers: [
    {
      provide: WALLET_NOW_PROVIDER,
      useValue: () => new Date(),
    },
    WalletService,
  ],
  exports: [WalletService, JwtModule],
})
export class WalletModule {}
