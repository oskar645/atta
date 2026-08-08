import { Module } from '@nestjs/common';

import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { WalletModule } from '../wallet/wallet.module';
import { PromotionsController } from './promotions.controller';
import { PromotionsService } from './promotions.service';

@Module({
  imports: [UserBlocksModule, WalletModule],
  controllers: [PromotionsController],
  providers: [PromotionsService],
  exports: [PromotionsService],
})
export class PromotionsModule {}
