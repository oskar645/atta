import { Body, Controller, Post, Req } from '@nestjs/common';

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
  start(@Req() request: any, @Body() dto: StartPhoneVerificationDto) {
    return this.phoneVerificationService.startCallVerification(
      dto.phone,
      dto.purpose,
      {
        deviceId: this.headerValue(request, 'x-device-id') ||
          this.headerValue(request, 'x-client-device-id'),
        ip: this.clientIp(request),
        userAgent: this.headerValue(request, 'user-agent'),
      },
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

  private headerValue(request: any, name: string) {
    return `${request?.headers?.[name] ?? ''}`.trim();
  }

  private clientIp(request: any) {
    const forwarded = this.headerValue(request, 'x-forwarded-for');
    return (
      `${request?.ip ?? ''}`.trim() ||
      forwarded.split(',')[0]?.trim() ||
      'unknown'
    );
  }
}
