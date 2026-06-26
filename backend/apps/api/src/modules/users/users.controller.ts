import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  UseGuards,
} from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthenticatedUser } from '../auth/auth.types';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @UseGuards(JwtAuthGuard)
  @Get('me')
  getMe(@CurrentUser() authUser: AuthenticatedUser) {
    return this.usersService.getMe(authUser);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('me')
  updateMe(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() dto: UpdateProfileDto,
  ) {
    return this.usersService.updateMe(authUser, dto);
  }

  @Get('public/:id')
  getSellerPublicProfile(@Param('id') id: string) {
    return this.usersService.getSellerPublicProfile(id);
  }

  @UseGuards(JwtAuthGuard)
  @Get('admin/list')
  getAdminUsersList(@CurrentUser() authUser: AuthenticatedUser) {
    return this.usersService.getAdminUsersList(authUser);
  }
}
