import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';

import { AuthService } from './auth.service';
import { AppVisitsService } from '../app-visits/app-visits.service';
import { CurrentUser } from './current-user.decorator';
import { LoginDto } from './dto/login.dto';
import { LoginPhoneDto } from './dto/login-phone.dto';
import { LogoutDto } from './dto/logout.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { ResetPasswordPhoneDto } from './dto/reset-password-phone.dto';
import { SignupDto } from './dto/signup.dto';
import { SignupPhoneDto } from './dto/signup-phone.dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthenticatedUser } from './auth.types';
import { RateLimitService } from '../rate-limit/rate-limit.service';

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly appVisitsService: AppVisitsService,
    private readonly rateLimitService: RateLimitService,
  ) {}

  private rateKey(request: any, action: string) {
    const forwarded = request?.headers?.['x-forwarded-for']?.toString() ?? '';
    const ip =
      request?.ip?.toString().trim() ||
      forwarded.split(',')[0]?.trim() ||
      'unknown';
    return `auth:${action}:${ip}`;
  }

  @Post('signup')
  async signup(@Req() request: any, @Body() dto: SignupDto) {
    await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'signup'), {
      limit: 6,
      windowMs: 60 * 1000,
    });
    return this.authService.signup(dto);
  }

  @Post('login')
  async login(@Req() request: any, @Body() dto: LoginDto) {
    await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'login'), {
      limit: 8,
      windowMs: 60 * 1000,
    });
    return this.authService.login(dto);
  }

  @Post('signup-phone')
  async signupPhone(@Req() request: any, @Body() dto: SignupPhoneDto) {
    await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'signup-phone'), {
      limit: 6,
      windowMs: 60 * 1000,
    });
    return this.authService.signupPhone(dto);
  }

  @Post('referrals/open')
  async recordReferralOpen(
    @Req() request: any,
    @Body()
    dto: {
      referralCode?: string;
      referral_code?: string;
      appOpened?: boolean;
      app_opened?: boolean;
    },
  ) {
    await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'referrals-open'), {
      limit: 30,
      windowMs: 60 * 1000,
    });
    return this.authService.recordReferralAppOpen(dto);
  }

  @Post('login-phone')
  async loginPhone(@Req() request: any, @Body() dto: LoginPhoneDto) {
    await this.rateLimitService.consumeOrThrow(this.rateKey(request, 'login-phone'), {
      limit: 8,
      windowMs: 60 * 1000,
    });
    return this.authService.loginPhone(dto);
  }

  @Post('reset-password-phone')
  async resetPasswordPhone(@Req() request: any, @Body() dto: ResetPasswordPhoneDto) {
    await this.rateLimitService.consumeOrThrow(
      this.rateKey(request, 'reset-password-phone'),
      {
        limit: 5,
        windowMs: 60 * 1000,
      },
    );
    return this.authService.resetPasswordPhone(dto);
  }

  @UseGuards(JwtAuthGuard)
  @Get('me')
  getMe(@CurrentUser() authUser: AuthenticatedUser) {
    return this.authService.getMe(authUser);
  }

  @UseGuards(JwtAuthGuard)
  @Post('app-open')
  markAppOpened(@CurrentUser() authUser: AuthenticatedUser) {
    return this.appVisitsService.markAppOpened(authUser.userId);
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto);
  }

  @UseGuards(JwtAuthGuard)
  @Post('logout')
  logout(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: LogoutDto,
  ) {
    return this.authService.logout(authUser, dto);
  }

  @UseGuards(JwtAuthGuard)
  @Post('sessions/revoke-others')
  revokeOtherSessions(@CurrentUser() authUser: AuthenticatedUser) {
    return this.authService.revokeOtherSessions(authUser);
  }

  @UseGuards(JwtAuthGuard)
  @Post('sessions/revoke-all')
  revokeAllSessions(@CurrentUser() authUser: AuthenticatedUser) {
    return this.authService.revokeAllSessions(authUser);
  }

  @UseGuards(JwtAuthGuard)
  @Delete('account')
  deleteAccount(@CurrentUser() authUser: AuthenticatedUser) {
    return this.authService.deleteAccount(authUser);
  }
}
