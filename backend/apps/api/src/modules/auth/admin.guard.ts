import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';

import { AuthenticatedUser } from './auth.types';

@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<{
      authUser?: AuthenticatedUser;
    }>();

    if (request.authUser?.role !== 'admin') {
      throw new ForbiddenException('Доступ разрешён только администраторам');
    }

    return true;
  }
}
