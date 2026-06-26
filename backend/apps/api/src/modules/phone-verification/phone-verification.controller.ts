import { Body, Controller, Post } from '@nestjs/common';

import { CheckPhoneRegistrationDto } from './dto/check-phone-registration.dto';
import { CheckPhoneVerificationDto } from './dto/check-phone-verification.dto';
import { StartPhoneVerificationDto } from './dto/start-phone-verification.dto';
import { PhoneVerificationService } from './phone-verification.service';

@Controller('auth/phone')
export class PhoneVerificationController {
  constructor(
    private readonly phoneVerificationService: PhoneVerificationService,
  ) {}

  @Post('check-registration')
  checkRegistration(@Body() dto: CheckPhoneRegistrationDto) {
    return this.phoneVerificationService.checkRegistration(dto.phone);
  }

  @Post('start')
  start(@Body() dto: StartPhoneVerificationDto) {
    return this.phoneVerificationService.startCallVerification(
      dto.phone,
      dto.purpose,
    );
  }

  @Post('check')
  check(@Body() dto: CheckPhoneVerificationDto) {
    return this.phoneVerificationService.checkCallVerification(
      dto.phone,
      dto.verificationId ?? dto.checkId ?? '',
      dto.purpose,
    );
  }
}
