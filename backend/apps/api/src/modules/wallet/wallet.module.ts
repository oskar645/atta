import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';

import { env } from '../../config/env';
import { WalletController } from './wallet.controller';
import { WalletService } from './wallet.service';

@Module({
  imports: [
    JwtModule.register({
      secret: env.JWT_ACCESS_SECRET,
    }),
  ],
  controllers: [WalletController],
  providers: [WalletService],
  exports: [WalletService, JwtModule],
})
export class WalletModule {}
