import { Body, Controller, HttpException, Post, Req, Res } from '@nestjs/common';
import { createHash } from 'crypto';
import { RateLimitService } from '../rate-limit/rate-limit.service';
import { PasswordlessCheckDto, PasswordlessCompleteDto, PasswordlessStartDto } from './dto/passwordless.dto';
import { PasswordlessService } from './passwordless.service';

@Controller('auth/passwordless')
export class PasswordlessController {
  constructor(private readonly passwordless: PasswordlessService, private readonly rateLimit: RateLimitService) {}

  @Post('start')
  start(@Req() request: any, @Res({ passthrough: true }) response: any, @Body() dto: PasswordlessStartDto) {
    return this.run('start', request, response, () => this.passwordless.start(dto.phone, {
      ip: request.ip,
      deviceId: request.headers?.['x-device-id'] || request.headers?.['x-client-device-id'],
      userAgent: request.headers?.['user-agent'],
    }, dto));
  }

  @Post('check')
  check(@Req() request: any, @Res({ passthrough: true }) response: any, @Body() dto: PasswordlessCheckDto) {
    return this.run('check', request, response, () => this.passwordless.check(dto.challenge));
  }

  @Post('complete')
  complete(@Req() request: any, @Res({ passthrough: true }) response: any, @Body() dto: PasswordlessCompleteDto) {
    return this.run('complete', request, response, () => this.passwordless.complete(dto));
  }

  private async run<T>(action: string, request: any, response: any, work: () => Promise<T>) {
    response.setHeader('Cache-Control', 'no-store');
    try {
      const signals = [request.ip || 'unknown', request.headers?.['x-device-id'] || request.headers?.['x-client-device-id']];
      for (const [index, signal] of signals.entries()) {
        if (!signal) continue;
        const key = createHash('sha256').update(String(signal)).digest('hex');
        await this.rateLimit.consumeOrThrow(`passwordless:${action}:source:${index}:${key}`, {
          limit: action === 'check' ? 60 : 10, windowMs: 60_000,
        });
      }
      const result = await work();
      if (result && typeof result === 'object' && 'retryAfterSeconds' in result &&
          typeof result.retryAfterSeconds === 'number') {
        response.setHeader('Retry-After', String(result.retryAfterSeconds));
      }
      return result;
    } catch (error) {
      if (error instanceof HttpException && error.getStatus() === 429) response.setHeader('Retry-After', '60');
      throw error;
    }
  }
}
