import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';

import { env } from '../../config/env';
import { AppVisitsModule } from '../app-visits/app-visits.module';
import { StorageModule } from '../storage/storage.module';
import { WalletModule } from '../wallet/wallet.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { AdminGuard } from './admin.guard';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { OptionalJwtAuthGuard } from './optional-jwt-auth.guard';

@Module({
  imports: [
    AppVisitsModule,
    StorageModule,
    WalletModule,
    UserBlocksModule,
    JwtModule.register({
      secret: env.JWT_ACCESS_SECRET,
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtAuthGuard, OptionalJwtAuthGuard, AdminGuard],
  exports: [AuthService, JwtAuthGuard, OptionalJwtAuthGuard, AdminGuard, JwtModule],
})
export class AuthModule {}
