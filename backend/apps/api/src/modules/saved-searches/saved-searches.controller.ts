import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SavedSearchesService } from './saved-searches.service';

@Controller('saved-searches')
@UseGuards(JwtAuthGuard)
export class SavedSearchesController {
  constructor(private readonly savedSearchesService: SavedSearchesService) {}

  @Get()
  list(@CurrentUser() authUser: AuthenticatedUser) {
    return this.savedSearchesService.list(authUser);
  }

  @Post()
  save(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: Record<string, unknown>,
  ) {
    return this.savedSearchesService.upsert(authUser, body);
  }

  @Patch(':id')
  update(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.savedSearchesService.update(authUser, id, body);
  }

  @Delete(':id')
  remove(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') id: string,
  ) {
    return this.savedSearchesService.remove(authUser, id);
  }
}
