import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';

import { CurrentUser } from './current-user.decorator';
import { AuthenticatedUser } from './auth.types';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AccountRecoveryService } from './account-recovery.service';
import {
  CompleteRecoveryPhoneDto,
  StartRecoveryEmailDto,
  StartRecoveryPhoneDto,
  VerifyEmailCodeDto,
} from './dto/account-recovery.dto';

@Controller('auth/recovery-email')
export class RecoveryEmailController {
  constructor(private readonly recovery: AccountRecoveryService) {}

  @Post('start')
  @UseGuards(JwtAuthGuard)
  start(@CurrentUser() user: AuthenticatedUser, @Body() body: StartRecoveryEmailDto, @Req() req: any) {
    return this.recovery.startRecoveryEmail(user.userId, body.email, this.source(req));
  }

  @Post('verify')
  @UseGuards(JwtAuthGuard)
  verify(@CurrentUser() user: AuthenticatedUser, @Body() body: VerifyEmailCodeDto) {
    return this.recovery.verifyRecoveryEmail(user.userId, body.challengeId, body.code);
  }

  private source(req: any) {
    return { ip: req?.ip?.toString(), deviceId: req?.headers?.['x-device-id']?.toString() };
  }
}

@Controller('auth/account-recovery')
export class AccountRecoveryController {
  constructor(private readonly recovery: AccountRecoveryService) {}

  @Post('start')
  start(@Body() body: StartRecoveryEmailDto, @Req() req: any) {
    return this.recovery.startAccountRecovery(body.email, this.source(req));
  }

  @Post('verify-email')
  verifyEmail(@Body() body: VerifyEmailCodeDto, @Req() req: any) {
    return this.recovery.verifyAccountRecoveryEmail(body.challengeId, body.code, this.source(req));
  }

  @Post('phone/start')
  startPhone(@Body() body: StartRecoveryPhoneDto, @Req() req: any) {
    return this.recovery.startPhone(body.recoveryToken, body.phone, this.source(req));
  }

  @Post('phone/complete')
  completePhone(@Body() body: CompleteRecoveryPhoneDto) {
    return this.recovery.completePhone(body.recoveryToken, body.phone, body.verificationCheckId);
  }

  private source(req: any) {
    return { ip: req?.ip?.toString(), deviceId: req?.headers?.['x-device-id']?.toString(), userAgent: req?.headers?.['user-agent']?.toString() };
  }
}
