import { Module } from '@nestjs/common';

import { PrismaModule } from '../prisma/prisma.module';
import { PhoneVerificationController } from './phone-verification.controller';
import { PhoneVerificationService } from './phone-verification.service';

@Module({
  imports: [PrismaModule],
  controllers: [PhoneVerificationController],
  providers: [PhoneVerificationService],
  exports: [PhoneVerificationService],
})
export class PhoneVerificationModule {}
