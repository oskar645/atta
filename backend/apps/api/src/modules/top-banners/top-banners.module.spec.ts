import assert from 'node:assert/strict';
import test from 'node:test';

import { Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitModule } from '../rate-limit/rate-limit.module';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { TopBannersModule } from './top-banners.module';

@Module({ imports: [RateLimitModule, TopBannersModule] })
class TopBannersModuleTestRoot {}

test('TopBannersModule compiles with all JwtAuthGuard dependencies', async (t) => {
  const originalOnModuleInit = PrismaService.prototype.onModuleInit;
  PrismaService.prototype.onModuleInit = async () => undefined;
  t.after(() => {
    PrismaService.prototype.onModuleInit = originalOnModuleInit;
  });

  const context = await NestFactory.createApplicationContext(TopBannersModuleTestRoot, {
    abortOnError: false,
    logger: false,
  });
  t.after(async () => context.close());

  assert.ok(context.get(JwtAuthGuard));
  assert.ok(context.get(PrismaService));
  assert.ok(context.get(UserBlocksService));
});
