import { Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UserFollowsService } from './user-follows.service';

@Controller('user-follows')
@UseGuards(JwtAuthGuard)
export class UserFollowsController {
  constructor(private readonly userFollowsService: UserFollowsService) {}

  @Get()
  list(@CurrentUser() authUser: AuthenticatedUser) {
    return this.userFollowsService.list(authUser);
  }

  @Get('seller/:sellerId/count')
  countFollowers(@Param('sellerId') sellerId: string) {
    return this.userFollowsService.countFollowers(sellerId);
  }

  @Post(':sellerId')
  follow(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('sellerId') sellerId: string,
  ) {
    return this.userFollowsService.follow(authUser, sellerId);
  }

  @Delete(':sellerId')
  unfollow(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('sellerId') sellerId: string,
  ) {
    return this.userFollowsService.unfollow(authUser, sellerId);
  }
}
