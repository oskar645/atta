import { Body, Controller, Post, Req } from '@nestjs/common';

import {
  CheckEmailPasswordlessDto,
  CompleteEmailPasswordlessDto,
  StartEmailPasswordlessDto,
} from './dto/email-passwordless.dto';
import { EmailPasswordlessService } from './email-passwordless.service';

@Controller('auth/email')
export class EmailPasswordlessController {
  constructor(private readonly emailPasswordless: EmailPasswordlessService) {}

  @Post('start')
  start(@Body() body: StartEmailPasswordlessDto, @Req() request: any) {
    return this.emailPasswordless.start(body.email, this.source(request));
  }

  @Post('check')
  check(@Body() body: CheckEmailPasswordlessDto, @Req() request: any) {
    return this.emailPasswordless.check(
      body.challengeId,
      body.code,
      this.source(request),
    );
  }

  @Post('complete')
  complete(@Body() body: CompleteEmailPasswordlessDto, @Req() request: any) {
    return this.emailPasswordless.complete(body, this.source(request));
  }

  private source(request: any) {
    const forwarded =
      request?.headers?.['x-forwarded-for']?.toString().split(',')[0]?.trim() ??
      '';
    return {
      ip: request?.ip?.toString().trim() || forwarded || 'unknown',
      deviceId: request?.headers?.['x-device-id']?.toString().trim() || '',
    };
  }
}
