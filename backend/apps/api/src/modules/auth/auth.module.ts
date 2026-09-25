import { AccountDeletionService } from './account-deletion.service';
import { forwardRef, Module } from '@nestjs/common';
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
import { RestoreCredentialsService } from './restore-credentials.service';
import { RedisModule } from '../redis/redis.module';
import { PhoneVerificationModule } from '../phone-verification/phone-verification.module';
import { PasswordlessController } from './passwordless.controller';
import { PasswordlessService } from './passwordless.service';
import { EmailModule } from '../email/email.module';
import { AccountRecoveryController, RecoveryEmailController } from './account-recovery.controller';
import { AccountRecoveryService } from './account-recovery.service';

@Module({
  imports: [
    AppVisitsModule,
    forwardRef(() => StorageModule),
    WalletModule,
    UserBlocksModule,
    RedisModule,
    PhoneVerificationModule,
    EmailModule,
    JwtModule.register({
      secret: env.JWT_ACCESS_SECRET,
    }),
  ],
  controllers: [AuthController, PasswordlessController, RecoveryEmailController, AccountRecoveryController],
  providers: [
    AuthService,
    PasswordlessService,
    AccountRecoveryService,
    AccountDeletionService,
    RestoreCredentialsService,
    JwtAuthGuard,
    OptionalJwtAuthGuard,
    AdminGuard,
  ],
  exports: [AccountDeletionService, AuthService, JwtAuthGuard, OptionalJwtAuthGuard, AdminGuard, JwtModule],
})
export class AuthModule {}
