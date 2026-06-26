import { Module } from '@nestjs/common';

import { ApnsService } from './apns.service';

@Module({
  providers: [ApnsService],
  exports: [ApnsService],
})
export class ApnsModule {}
