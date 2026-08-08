import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UserStatus } from '@prisma/client';

import { parseAdminPhoneNumbers } from '../../config/env';
import { normalizeRussianPhone } from '../../common/phone';
import { env } from '../../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { UserBlocksService } from '../user-blocks/user-blocks.service';
import { AuthenticatedUser, AuthTokenPayload } from './auth.types';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
    private readonly userBlocksService: UserBlocksService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<{
      method?: string;
      url?: string;
      path?: string;
      headers?: Record<string, string | string[] | undefined>;
      authUser?: AuthenticatedUser;
    }>();
    const authorizationHeader = request.headers?.authorization;
    const rawHeader = Array.isArray(authorizationHeader)
      ? authorizationHeader[0]
      : authorizationHeader;

    if (!rawHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Authorization header is missing');
    }

    const token = rawHeader.slice('Bearer '.length).trim();
    if (!token) {
      throw new UnauthorizedException('Access token is missing');
    }

    let payload: AuthTokenPayload;
    try {
      payload = await this.jwtService.verifyAsync<AuthTokenPayload>(token, {
        secret: env.JWT_ACCESS_SECRET,
      });
    } catch {
      throw new UnauthorizedException('Access token is invalid or expired');
    }

    if (payload.type !== 'access') {
      throw new UnauthorizedException('Access token type is invalid');
    }

    const session = await this.prisma.userSession.findFirst({
      where: {
        id: payload.sessionId,
        userId: payload.sub,
        revokedAt: null,
      },
      select: {
        id: true,
        expiresAt: true,
        user: {
          select: {
            id: true,
            email: true,
            phone: true,
            status: true,
            deletedAt: true,
            adminProfile: {
              select: {
                isAdmin: true,
              },
            },
          },
        },
      },
    });

    if (!session) {
      throw new UnauthorizedException('Session is not active');
    }

    if (session.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException('Session has expired');
    }

    if (session.user.status === UserStatus.DELETED || session.user.deletedAt) {
      throw new UnauthorizedException('User account is deleted');
    }

    const authUser = {
      userId: session.user.id,
      sessionId: session.id,
      email: session.user.email,
      role: this.resolveRole(
        session.user.adminProfile?.isAdmin === true,
        session.user.phone,
      ),
    };
    request.authUser = authUser;

    if (authUser.role !== 'admin' && this.shouldBlockWriteRequest(request)) {
      const block = await this.userBlocksService.getActiveBlock(authUser.userId);
      if (block) {
        throw new ForbiddenException({
          code: 'ACCOUNT_BLOCKED',
          message: 'Аккаунт заблокирован',
          blockId: block.id,
          reason: block.reason,
          endsAt: block.endsAt?.toISOString() ?? null,
          permanent: block.type === 'PERMANENT',
        });
      }
    }

    return true;
  }

  private shouldBlockWriteRequest(request: {
    method?: string;
    url?: string;
    path?: string;
  }) {
    const method = (request.method ?? 'GET').toUpperCase();
    if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') {
      return false;
    }
    const path = (request.path ?? request.url ?? '').split('?')[0] ?? '';
    if (path === '/auth/logout') return false;
    if (path.startsWith('/support')) return false;
    return true;
  }

  private resolveRole(isAdminFromDb: boolean, phone: string | null) {
    if (isAdminFromDb) {
      return 'admin' as const;
    }

    const normalizedPhone = normalizeRussianPhone(phone ?? '');
    if (!normalizedPhone) {
      return 'user' as const;
    }

    return new Set(parseAdminPhoneNumbers()).has(normalizedPhone)
        ? 'admin'
        : 'user';
  }
}
