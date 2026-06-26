import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UserStatus } from '@prisma/client';

import { normalizeRussianPhone } from '../../common/phone';
import { parseAdminPhoneNumbers } from '../../config/env';
import { env } from '../../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { AuthenticatedUser, AuthTokenPayload } from './auth.types';

@Injectable()
export class OptionalJwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<{
      headers?: Record<string, string | string[] | undefined>;
      authUser?: AuthenticatedUser;
    }>();
    const authorizationHeader = request.headers?.authorization;
    const rawHeader = Array.isArray(authorizationHeader)
      ? authorizationHeader[0]
      : authorizationHeader;

    if (!rawHeader?.startsWith('Bearer ')) {
      return true;
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

    request.authUser = {
      userId: session.user.id,
      sessionId: session.id,
      email: session.user.email,
      role: this.resolveRole(
        session.user.adminProfile?.isAdmin === true,
        session.user.phone,
      ),
    };

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
