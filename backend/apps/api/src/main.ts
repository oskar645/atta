import 'reflect-metadata';

import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { join } from 'path';

import { AppModule } from './app.module';
import { configureTrustProxy } from './common/trust-proxy';
import { env, parseCorsOrigins } from './config/env';
import { StorageService } from './modules/storage/storage.service';

const express = require('express') as {
  static: (path: string) => unknown;
};

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    cors: {
      origin: parseCorsOrigins(),
      credentials: true,
    },
  });
  configureTrustProxy(app.getHttpAdapter().getInstance());

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  app.use((req: any, res: any, next: () => void) => {
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    next();
  });

  const storageService = app.get(StorageService);
  await storageService.ensureUploadsDirs();
  const uploadsRoot = storageService.getUploadsRoot();
  app.use(
    '/uploads/avatars',
    express.static(join(uploadsRoot, 'avatars')),
  );
  app.use(
    '/uploads/listings',
    express.static(join(uploadsRoot, 'listings')),
  );
  app.use(
    '/uploads/feed-ads',
    express.static(join(uploadsRoot, 'feed-ads')),
  );

  await app.listen(env.PORT);

  const logger = new Logger('Bootstrap');
  logger.log(`ATTA backend skeleton is running on port ${env.PORT}`);
}

void bootstrap();
