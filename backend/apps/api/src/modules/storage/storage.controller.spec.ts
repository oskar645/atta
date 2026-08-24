import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Module } from '@nestjs/common';
import { GUARDS_METADATA } from '@nestjs/common/constants';
import { NestFactory } from '@nestjs/core';

import { AdminGuard } from '../auth/admin.guard';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PrismaService } from '../prisma/prisma.service';
import { RateLimitModule } from '../rate-limit/rate-limit.module';
import { StorageController } from './storage.controller';
import { StorageModule } from './storage.module';

PrismaService.prototype.onModuleInit = async () => undefined;

@Module({
  imports: [RateLimitModule, StorageModule],
})
class StorageModuleTestRoot {}

test('legacy storage routes are guarded by jwt and admin access', () => {
  const guards = Reflect.getMetadata(GUARDS_METADATA, StorageController) ?? [];

  assert.deepEqual(guards, [JwtAuthGuard, AdminGuard]);
});

test('storage module initializes with jwt guard dependencies', async () => {
  const app = await NestFactory.create(StorageModuleTestRoot, {
    abortOnError: false,
    logger: false,
  });

  try {
    await app.init();
    assert.ok(app.get(JwtAuthGuard));
  } finally {
    await app.close();
  }
});

test('admin guard rejects regular user before storage delete can run', () => {
  const guard = new AdminGuard();
  const context = {
    switchToHttp: () => ({
      getRequest: () => ({
        authUser: {
          userId: 'user-1',
          role: 'user',
        },
      }),
    }),
  };

  assert.throws(() => guard.canActivate(context as any), {
    message: 'Доступ разрешён только администраторам',
  });
});
