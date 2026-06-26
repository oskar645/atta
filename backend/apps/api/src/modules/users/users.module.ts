import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { StorageModule } from '../storage/storage.module';
import { WalletModule } from '../wallet/wallet.module';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [AuthModule, StorageModule, WalletModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
