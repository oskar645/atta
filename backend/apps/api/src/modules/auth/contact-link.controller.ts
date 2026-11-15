import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';

import { AuthenticatedUser } from './auth.types';
import { ContactLinkService } from './contact-link.service';
import { CurrentUser } from './current-user.decorator';
import { CompleteLinkPhoneDto, StartLinkPhoneDto } from './dto/link-phone.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@Controller('auth/link-phone')
@UseGuards(JwtAuthGuard)
export class ContactLinkController {
  constructor(private readonly contactLink: ContactLinkService) {}

  @Post('start')
  start(
    @CurrentUser() user: AuthenticatedUser,
    @Body() body: StartLinkPhoneDto,
    @Req() request: any,
  ) {
    return this.contactLink.startPhone(user, body.phone, {
      ip: request?.ip?.toString(),
      deviceId: request?.headers?.['x-device-id']?.toString(),
      userAgent: request?.headers?.['user-agent']?.toString(),
    });
  }

  @Post('complete')
  complete(
    @CurrentUser() user: AuthenticatedUser,
    @Body() body: CompleteLinkPhoneDto,
  ) {
    return this.contactLink.completePhone(
      user,
      body.phone,
      body.verificationId,
    );
  }
}
