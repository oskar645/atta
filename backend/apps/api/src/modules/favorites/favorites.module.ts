import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { UserBlocksModule } from '../user-blocks/user-blocks.module';
import { FavoritesController } from './favorites.controller';
import { FavoritesService } from './favorites.service';

@Module({
  imports: [AuthModule, UserBlocksModule],
  controllers: [FavoritesController],
  providers: [FavoritesService],
  exports: [FavoritesService],
})
export class FavoritesModule {}
