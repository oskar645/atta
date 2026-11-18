import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  Optional,
} from '@nestjs/common';
import {
  NotificationType,
  Prisma,
  SupportSenderType,
  SupportTicketStatus,
  SupportTicketCategory,
} from '@prisma/client';
import { createHash, randomBytes } from 'crypto';
import { CreatePublicSupportTicketDto } from './dto/public-support.dto';

import { AuthenticatedUser } from '../auth/auth.types';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { normalizeStoredMediaUrl } from '../../common/serializers';
import { ListAdminSupportTicketsDto } from './dto/list-admin-support-tickets.dto';
import { AdminDashboardSignal } from '../../common/admin-dashboard-signal';
import { SupportRealtimeSignal } from '../../common/support-realtime-signal';
import { detectImageMime } from '../media/image-upload';

@Injectable()
export class SupportService {
  private static readonly contentPrefix = '__atta_support_payload__:';

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
    private readonly storageService: StorageService,
    @Optional() private readonly adminDashboardSignal?: AdminDashboardSignal,
    @Optional() private readonly supportRealtimeSignal?: SupportRealtimeSignal,
  ) {}

  private async notifyAdminsOfSupport(params: {
    ticketId: string;
    eventId: string;
    isNewTicket: boolean;
  }) {
    try {
      await this.notificationsService.createAdminEventNotifications({
        eventKey: `admin_support:${params.isNewTicket ? 'ticket' : 'message'}:${params.eventId}`,
        title: 'ATTA — Техподдержка',
        body: params.isNewTicket
          ? 'Поступило новое обращение пользователя.'
          : 'Новое сообщение в техподдержке.',
        type: NotificationType.SUPPORT,
        payload: {
          actionType: 'admin_support_new',
          ticketId: params.ticketId,
        },
      });
    } catch {
      // Administrative delivery must not roll back a completed support write.
    }
  }

  private pageLimit(value: number | undefined, fallback = 50) {
    const parsed = Number(value ?? fallback);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(Math.max(Math.trunc(parsed), 1), 100);
  }

  private encodeAdminCursor(value: Record<string, string>) {
    return Buffer.from(JSON.stringify(value)).toString('base64url');
  }

  private decodeAdminCursor(cursor?: string) {
    const normalized = cursor?.trim();
    if (!normalized) return null;
    try {
      const parsed = JSON.parse(
        Buffer.from(normalized, 'base64url').toString('utf8'),
      );
      if (!parsed || typeof parsed !== 'object') return null;
      return parsed as Record<string, string>;
    } catch {
      return null;
    }
  }

  private decodeContent(rawText: string | null | undefined) {
    const text = rawText?.trim() ?? '';
    if (!text.startsWith(SupportService.contentPrefix)) {
      return {
        text,
        imageUrl: '',
      };
    }

    try {
      const payload = JSON.parse(
        text.slice(SupportService.contentPrefix.length),
      ) as { text?: string; image_url?: string };
      return {
        text: payload.text?.trim() ?? '',
        imageUrl: payload.image_url?.trim() ?? '',
      };
    } catch {
      return {
        text,
        imageUrl: '',
      };
    }
  }

  private encodeContent(params: { text?: string; imageUrl?: string }) {
    const text = params.text?.trim() ?? '';
    const imageUrl = params.imageUrl?.trim() ?? '';
    if (imageUrl.length === 0) {
      return text;
    }
    return `${SupportService.contentPrefix}${JSON.stringify({
      text,
      image_url: imageUrl,
    })}`;
  }

  private previewText(rawText: string | null | undefined) {
    const content = this.decodeContent(rawText);
    if (content.imageUrl.length === 0) {
      return content.text;
    }
    if (content.text.length === 0) {
      return 'Фото';
    }
    return `${content.text} · Фото`;
  }

  private notificationPreview(rawText: string | null | undefined) {
    const preview = this.previewText(rawText).replace(/\s+/g, ' ').trim();
    if (preview.length <= 120) return preview;
    return `${preview.slice(0, 117).trim()}...`;
  }

  private adminContactIdempotencyKey(userId: string, rawKey?: string) {
    const key = rawKey?.trim() ?? '';
    if (!key) {
      return null;
    }
    return `support_admin_contact:${userId}:${key}`;
  }

  private serializeMessage(message: {
    id: string;
    ticketId: string;
    sender: SupportSenderType;
    text: string;
    createdAt: Date;
    senderUserId?: string | null;
    idempotencyKey?: string | null;
    readAt?: Date | null;
    editedAt?: Date | null;
    deletedAt?: Date | null;
    deletedByUserId?: string | null;
  }) {
    const content = this.decodeContent(message.text);
    const deleted = message.deletedAt != null;
    return {
      id: message.id,
      ticket_id: message.ticketId,
      sender: message.sender.toLowerCase(),
      text: deleted ? '' : content.text,
      image_url:
        deleted ? null : normalizeStoredMediaUrl(content.imageUrl, {
          category: 'support',
        }) || null,
      sender_user_id: message.senderUserId ?? null,
      client_operation_id: message.idempotencyKey ?? null,
      created_at: message.createdAt.toISOString(),
      read_at: message.readAt?.toISOString() ?? null,
      edited_at: message.editedAt?.toISOString() ?? null,
      deleted_at: message.deletedAt?.toISOString() ?? null,
      deleted_by_user_id: message.deletedByUserId ?? null,
    };
  }

  private supportMessageOrder() {
    return [{ createdAt: 'desc' as const }, { id: 'desc' as const }];
  }

  private emitSupportChanged(params: {
    ticketId: string;
    userId: string | null;
    messageId?: string;
    action: 'created' | 'updated' | 'deleted' | 'read';
  }) {
    this.supportRealtimeSignal?.changed(params);
  }

  private validateIdempotentMessage(
    message: {
      ticketId: string;
      sender: SupportSenderType;
      senderUserId: string | null;
      text: string;
    },
    expected: {
      ticketId: string;
      sender: SupportSenderType;
      senderUserId: string;
      text: string;
    },
  ) {
    if (
      message.ticketId !== expected.ticketId ||
      message.sender !== expected.sender ||
      message.senderUserId !== expected.senderUserId ||
      message.text !== expected.text
    ) {
      throw new ConflictException('Ключ отправки уже использован для другого сообщения');
    }
  }

  private serializeTicket(ticket: {
    id: string;
    userId: string | null;
    category?: SupportTicketCategory;
    contactPhone?: string | null;
    contactEmail?: string | null;
    name: string;
    subject: string;
    status: SupportTicketStatus;
    lastMessage: string;
    unreadForAdmin: boolean;
    unreadForUser: boolean;
    createdAt: Date;
    updatedAt: Date;
    messages?: Array<{ sender: SupportSenderType }>;
  }) {
    const firstSender = ticket.messages?.[0]?.sender;
    return {
      id: ticket.id,
      uid: ticket.userId,
      user_id: ticket.userId,
      category: (ticket.category ?? SupportTicketCategory.GENERAL).toLowerCase(),
      contact_phone: ticket.contactPhone ?? null,
      contact_email: ticket.contactEmail ?? null,
      name: ticket.name,
      subject: ticket.subject,
      status: ticket.status.toLowerCase(),
      last_message: this.previewText(ticket.lastMessage),
      unread_for_admin: ticket.unreadForAdmin,
      unread_for_user: ticket.unreadForUser,
      initiated_by:
        firstSender == null ? null : firstSender.toString().toLowerCase(),
      created_at: ticket.createdAt.toISOString(),
      updated_at: ticket.updatedAt.toISOString(),
    };
  }

  requireImage(
    file: UploadedImageFile | undefined,
    maxSizeBytes: number,
  ): UploadedImageFile {
    if (!file || !file.buffer || file.size === 0) {
      throw new BadRequestException('Изображение обязательно');
    }

    const mime = file.mimetype.trim().toLowerCase();
    const allowed = new Set(['image/jpeg', 'image/png', 'image/webp']);
    if (!allowed.has(mime)) {
      throw new BadRequestException('Поддерживаются JPG, PNG и WEBP');
    }
    if (detectImageMime(file.buffer) !== mime) {
      throw new BadRequestException('Файл не является корректным изображением');
    }
    if (file.size > maxSizeBytes) {
      throw new BadRequestException('Файл слишком большой');
    }
    return file;
  }

  async uploadImage(
    authUser: AuthenticatedUser,
    file: UploadedImageFile,
    ticketId?: string,
  ) {
    const media = await this.storageService.saveUploadedFile({
      buffer: file.buffer,
      category: 'support',
      contentType: file.mimetype,
      context: {
        ticketId,
        userId: authUser.userId,
      },
      originalName: file.originalname,
    });

    return {
      source: 'timeweb',
      url: normalizeStoredMediaUrl(media.url, {
        category: 'support',
        providerHint: media.provider,
        storageKey: media.key,
      }),
    };
  }

  async listMyTickets(authUser: AuthenticatedUser) {
    const items = await this.prisma.supportTicket.findMany({
      where: {
        userId: authUser.userId,
      },
      include: {
        messages: {
          orderBy: {
            createdAt: 'asc',
          },
          take: 1,
        },
      },
      orderBy: {
        updatedAt: 'desc',
      },
    });

    return {
      source: 'timeweb',
      items: items.map((ticket) => this.serializeTicket(ticket)),
    };
  }

  async listTickets(query: ListAdminSupportTicketsDto = {}) {
    const limit = this.pageLimit(query.limit);
    const decoded = this.decodeAdminCursor(query.cursor);
    const rawUpdatedAt = decoded?.updatedAt;
    const cursorDate = rawUpdatedAt ? new Date(rawUpdatedAt) : null;
    const cursorId = decoded?.id;
    const [items, unreadForAdmin] = await Promise.all([
      this.prisma.supportTicket.findMany({
        where: {
          ...(query.category ? { category: query.category } : {}),
          ...(cursorDate && !Number.isNaN(cursorDate.getTime()) && cursorId
            ? {
                OR: [
                  { updatedAt: { lt: cursorDate } },
                  { updatedAt: cursorDate, id: { lt: cursorId } },
                ],
              }
            : {}),
        },
        include: {
          messages: {
            orderBy: {
              createdAt: 'asc',
            },
            take: 1,
          },
        },
        orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
        take: limit + 1,
      }),
      this.prisma.supportTicket.count({
        where: {
          unreadForAdmin: true,
          ...(query.category ? { category: query.category } : {}),
        },
      }),
    ]);
    const pageItems = items.slice(0, limit);
    const last = items.length > limit ? pageItems[pageItems.length - 1] : null;

    return {
      source: 'timeweb',
      items: pageItems.map((ticket) => this.serializeTicket(ticket)),
      nextCursor: last
        ? this.encodeAdminCursor({
            updatedAt: last.updatedAt.toISOString(),
            id: last.id,
          })
        : null,
      hasMore: items.length > limit,
      limit,
      unreadForAdmin,
      unread_for_admin: unreadForAdmin,
    };
  }

  async openTicketForAdminContact(params: {
    userId?: string;
    name?: string;
    subject?: string;
    text?: string;
    idempotencyKey?: string;
  }) {
    const userId = params.userId?.trim() ?? '';
    const subject = params.subject?.trim() || 'Обращение в поддержку';
    const text = params.text?.trim() ?? '';
    if (!userId) {
      throw new BadRequestException('Не указан пользователь');
    }
    if (!text) {
      throw new BadRequestException('Сообщение обязательно');
    }
    const idempotencyKey = this.adminContactIdempotencyKey(
      userId,
      params.idempotencyKey,
    );

    const user = await this.prisma.user.findUnique({
      where: {
        id: userId,
      },
    });
    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    if (idempotencyKey) {
      const duplicate = await this.prisma.supportMessage.findUnique({
        where: {
          idempotencyKey,
        },
        include: {
          ticket: true,
        },
      });
      if (duplicate) {
        return {
          source: 'timeweb',
          ticketId: duplicate.ticketId,
          messageId: duplicate.id,
          created: false,
          ticket_created: false,
          ticket: this.serializeTicket(duplicate.ticket),
          item: this.serializeMessage(duplicate),
        };
      }
    }

    const name =
      params.name?.trim() ||
      user.displayName?.trim() ||
      user.name?.trim() ||
      'Пользователь';
    const encodedText = this.encodeContent({ text });
    const preview = this.previewText(encodedText);

    let result: {
      ticket: Prisma.SupportTicketGetPayload<Prisma.SupportTicketDefaultArgs>;
      message: Prisma.SupportMessageGetPayload<Prisma.SupportMessageDefaultArgs>;
      ticketCreated: boolean;
      messageCreated: boolean;
    };

    try {
      result = await this.prisma.$transaction(async (tx) => {
        await tx.$executeRaw`
          SELECT pg_advisory_xact_lock(
            hashtext(${`support_admin_contact:${userId}`})
          )
        `;

        if (idempotencyKey) {
          const duplicateInTx = await tx.supportMessage.findUnique({
            where: {
              idempotencyKey,
            },
            include: {
              ticket: true,
            },
          });
          if (duplicateInTx) {
            return {
              ticket: duplicateInTx.ticket,
              message: duplicateInTx,
              ticketCreated: false,
              messageCreated: false,
            };
          }
        }

        let ticket = await tx.supportTicket.findFirst({
          where: {
            userId,
            status: SupportTicketStatus.OPEN,
          },
          orderBy: {
            updatedAt: 'desc',
          },
        });
        let ticketCreated = false;

        if (!ticket) {
          ticket = await tx.supportTicket.create({
            data: {
              userId,
              name,
              subject,
              status: SupportTicketStatus.OPEN,
              lastMessage: preview,
              unreadForAdmin: false,
              unreadForUser: true,
            },
          });
          ticketCreated = true;
        }

        const message = await tx.supportMessage.create({
          data: {
            ticketId: ticket.id,
            sender: SupportSenderType.ADMIN,
            text: encodedText,
            ...(idempotencyKey ? { idempotencyKey } : {}),
          },
        });

        const updatedTicket = await tx.supportTicket.update({
          where: {
            id: ticket.id,
          },
          data: {
            status: SupportTicketStatus.OPEN,
            lastMessage: preview,
            unreadForAdmin: false,
            unreadForUser: true,
            subject: ticketCreated ? subject : ticket.subject,
            name: ticketCreated ? name : ticket.name,
          },
        });

        return {
          ticket: updatedTicket,
          message,
          ticketCreated,
          messageCreated: true,
        };
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const existing = idempotencyKey
          ? await this.prisma.supportMessage.findUnique({
              where: {
                idempotencyKey,
              },
              include: {
                ticket: true,
              },
            })
          : null;
        if (existing) {
          result = {
            ticket: existing.ticket,
            message: existing,
            ticketCreated: false,
            messageCreated: false,
          };
        } else {
          throw error;
        }
      } else {
        throw error;
      }
    }

    if (result.messageCreated) {
      try {
        await this.notificationsService.createSystemNotification({
          userId,
          title: 'Сообщение от администрации',
          body: this.notificationPreview(encodedText),
          type: NotificationType.SUPPORT,
          payload: {
            type: 'support_message',
            actionType: 'support_message',
            ticketId: result.ticket.id,
            userId,
            messageId: result.message.id,
          },
        });
      } catch {
        // Notification delivery is independent from the committed message.
      }
      this.emitSupportChanged({
        ticketId: result.ticket.id,
        userId,
        messageId: result.message.id,
        action: 'created',
      });
    }
    if (result.ticketCreated) this.adminDashboardSignal?.changed('support');

    return {
      source: 'timeweb',
      ticketId: result.ticket.id,
      messageId: result.message.id,
      created: result.ticketCreated,
      ticket_created: result.ticketCreated,
      ticket: this.serializeTicket(result.ticket),
      item: this.serializeMessage(result.message),
    };
  }

  async getTicketForUser(authUser: AuthenticatedUser, ticketId: string) {
    const ticket = await this.prisma.supportTicket.findFirst({
      where: {
        id: ticketId,
        userId: authUser.userId,
      },
      include: {
        messages: {
          orderBy: this.supportMessageOrder(),
        },
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(ticket),
      items: ticket.messages.map((message) => this.serializeMessage(message)),
    };
  }

  async getTicketForAdmin(ticketId: string) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: {
        id: ticketId,
      },
      include: {
        messages: {
          orderBy: this.supportMessageOrder(),
        },
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(ticket),
      items: ticket.messages.map((message) => this.serializeMessage(message)),
    };
  }

  async createTicket(
    authUser: AuthenticatedUser,
    params: {
      name?: string;
      subject?: string;
      text?: string;
      imageUrl?: string;
      idempotencyKey?: string;
    },
  ) {
    const text = params.text?.trim() ?? '';
    const imageUrl = params.imageUrl?.trim() ?? '';
    if (text.length === 0 && imageUrl.length === 0) {
      throw new BadRequestException('Сообщение или фото обязательны');
    }
    const name = params.name?.trim() || 'Пользователь';
    const subject = params.subject?.trim() || 'Обращение в поддержку';
    const encodedText = this.encodeContent({ text, imageUrl });
    const firstPreview = this.previewText(encodedText);
    const idempotencyKey = params.idempotencyKey?.trim() || null;

    const findExisting = async () => {
      if (!idempotencyKey) return null;
      const existing = await this.prisma.supportTicket.findUnique({
        where: { createIdempotencyKey: idempotencyKey },
        include: { messages: { orderBy: this.supportMessageOrder() } },
      });
      if (!existing) return null;
      const firstUserMessage = existing.messages
        .slice()
        .reverse()
        .find((message) => message.sender === SupportSenderType.USER);
      if (
        existing.userId !== authUser.userId ||
        firstUserMessage?.text !== encodedText
      ) {
        throw new ConflictException('Ключ отправки уже использован для другого обращения');
      }
      return existing;
    };

    let ticket = await findExisting();
    let created = false;
    if (!ticket) {
      try {
        ticket = await this.prisma.supportTicket.create({
          data: {
            userId: authUser.userId,
            name,
            subject,
            status: SupportTicketStatus.OPEN,
            lastMessage: firstPreview,
            unreadForAdmin: true,
            unreadForUser: false,
            ...(idempotencyKey ? { createIdempotencyKey: idempotencyKey } : {}),
            messages: {
              create: [
                {
                  sender: SupportSenderType.USER,
                  senderUserId: authUser.userId,
                  text: encodedText,
                },
                {
                  sender: SupportSenderType.ADMIN,
                  text:
                      'Здравствуйте! Мы получили ваше обращение и уже передали его модераторам. Обычно ответ приходит в ближайшее время.',
                },
              ],
            },
          },
          include: { messages: { orderBy: this.supportMessageOrder() } },
        });
        created = true;
      } catch (error) {
        if (
          !(error instanceof Prisma.PrismaClientKnownRequestError) ||
          error.code !== 'P2002' ||
          !idempotencyKey
        ) {
          throw error;
        }
        ticket = await findExisting();
        if (!ticket) throw error;
      }
    }
    if (!ticket) throw new ConflictException('Не удалось подтвердить обращение');
    if (!created) {
      return {
        source: 'timeweb',
        ticket: this.serializeTicket(ticket),
        items: ticket.messages.map((message) => this.serializeMessage(message)),
      };
    }
    this.adminDashboardSignal?.changed('support');
    await this.notifyAdminsOfSupport({
      ticketId: ticket.id,
      eventId: ticket.id,
      isNewTicket: true,
    });
    this.emitSupportChanged({
      ticketId: ticket.id,
      userId: ticket.userId,
      action: 'created',
    });

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(ticket),
      items: ticket.messages.map((message) => this.serializeMessage(message)),
    };
  }

  async createBlockAppeal(
    authUser: AuthenticatedUser,
    params: { text?: string; imageUrl?: string },
  ) {
    const text = params.text?.trim() ?? '';
    const imageUrl = params.imageUrl?.trim() ?? '';
    if (text.length === 0 && imageUrl.length === 0) {
      throw new BadRequestException('Сообщение или фото обязательны');
    }

    const block = await this.prisma.userBlock.findFirst({
      where: {
        userId: authUser.userId,
        status: 'ACTIVE',
        OR: [{ endsAt: null }, { endsAt: { gt: new Date() } }],
      },
      orderBy: {
        startsAt: 'desc',
      },
    });
    if (!block) {
      throw new BadRequestException('Активная блокировка не найдена');
    }

    const encodedText = this.encodeContent({
      text: [
        'Апелляция по блокировке аккаунта.',
        `blockId: ${block.id}`,
        block.listingId ? `listingId: ${block.listingId}` : null,
        `reason: ${block.reason}`,
        block.endsAt ? `endsAt: ${block.endsAt.toISOString()}` : 'permanent: true',
        '',
        text,
      ].filter((line): line is string => line != null).join('\n'),
      imageUrl,
    });
    const preview = this.previewText(encodedText);

    const user = await this.prisma.user.findUnique({
      where: {
        id: authUser.userId,
      },
    });

    const ticket = await this.prisma.supportTicket.create({
      data: {
        userId: authUser.userId,
        userBlockId: block.id,
        isBlockAppeal: true,
        name:
          user?.displayName?.trim() ||
          user?.name?.trim() ||
          user?.phone?.trim() ||
          'Пользователь',
        subject: 'Апелляция по блокировке',
        status: SupportTicketStatus.OPEN,
        lastMessage: preview,
        unreadForAdmin: true,
        unreadForUser: false,
        messages: {
          create: [
            {
              sender: SupportSenderType.USER,
              senderUserId: authUser.userId,
              text: encodedText,
            },
          ],
        },
      },
      include: {
        messages: {
          orderBy: this.supportMessageOrder(),
        },
      },
    });
    this.adminDashboardSignal?.changed('support');
    await this.notifyAdminsOfSupport({
      ticketId: ticket.id,
      eventId: ticket.id,
      isNewTicket: true,
    });

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(ticket),
      items: ticket.messages.map((message) => this.serializeMessage(message)),
    };
  }

  async sendMessageAsUser(
    authUser: AuthenticatedUser,
    ticketId: string,
    text?: string,
    imageUrl?: string,
    rawIdempotencyKey?: string,
  ) {
    const normalizedText = text?.trim() ?? '';
    const normalizedImageUrl = imageUrl?.trim() ?? '';
    if (normalizedText.length === 0 && normalizedImageUrl.length === 0) {
      throw new BadRequestException('Сообщение или фото обязательны');
    }
    const encodedText = this.encodeContent({
      text: normalizedText,
      imageUrl: normalizedImageUrl,
    });
    const idempotencyKey = rawIdempotencyKey?.trim() || null;
    const ticket = await this.prisma.supportTicket.findFirst({
      where: {
        id: ticketId,
        userId: authUser.userId,
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    const expected = {
      ticketId,
      sender: SupportSenderType.USER,
      senderUserId: authUser.userId,
      text: encodedText,
    };
    const findExisting = async () => {
      if (!idempotencyKey) return null;
      const existing = await this.prisma.supportMessage.findUnique({
        where: { idempotencyKey },
      });
      if (existing) this.validateIdempotentMessage(existing, expected);
      return existing;
    };
    let existing = await findExisting();
    let message = existing;
    let created = false;
    if (!message) {
      try {
        message = await this.prisma.$transaction(async (tx) => {
          const createdMessage = await tx.supportMessage.create({
            data: {
              ...expected,
              ...(idempotencyKey ? { idempotencyKey } : {}),
            },
          });
          await tx.supportTicket.update({
            where: { id: ticketId },
            data: {
              status: SupportTicketStatus.OPEN,
              lastMessage: this.previewText(createdMessage.text),
              unreadForAdmin: true,
              unreadForUser: false,
            },
          });
          return createdMessage;
        });
        created = true;
      } catch (error) {
        if (
          !(error instanceof Prisma.PrismaClientKnownRequestError) ||
          error.code !== 'P2002' ||
          !idempotencyKey
        ) throw error;
        message = await findExisting();
        if (!message) throw error;
      }
    }
    if (!message) throw new ConflictException('Не удалось подтвердить сообщение');
    if (!created) {
      return { source: 'timeweb', item: this.serializeMessage(message) };
    }
    this.adminDashboardSignal?.changed('support');
    await this.notifyAdminsOfSupport({
      ticketId,
      eventId: message.id,
      isNewTicket: false,
    });
    this.emitSupportChanged({
      ticketId,
      userId: ticket.userId,
      messageId: message.id,
      action: 'created',
    });

    return {
      source: 'timeweb',
      item: this.serializeMessage(message),
    };
  }

  async sendMessageAsAdmin(
    authUser: AuthenticatedUser,
    ticketId: string,
    text?: string,
    imageUrl?: string,
    rawIdempotencyKey?: string,
  ) {
    const normalizedText = text?.trim() ?? '';
    const normalizedImageUrl = imageUrl?.trim() ?? '';
    if (normalizedText.length === 0 && normalizedImageUrl.length === 0) {
      throw new BadRequestException('Сообщение или фото обязательны');
    }
    const ticket = await this.prisma.supportTicket.findUnique({
      where: {
        id: ticketId,
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    const encodedText = this.encodeContent({
      text: normalizedText,
      imageUrl: normalizedImageUrl,
    });
    const idempotencyKey = rawIdempotencyKey?.trim() || null;
    const expected = {
      ticketId,
      sender: SupportSenderType.ADMIN,
      senderUserId: authUser.userId,
      text: encodedText,
    };
    const findExisting = async () => {
      if (!idempotencyKey) return null;
      const existing = await this.prisma.supportMessage.findUnique({
        where: { idempotencyKey },
      });
      if (existing) this.validateIdempotentMessage(existing, expected);
      return existing;
    };
    let message = await findExisting();
    let created = false;
    if (!message) {
      try {
        message = await this.prisma.$transaction(async (tx) => {
          const createdMessage = await tx.supportMessage.create({
            data: {
              ...expected,
              ...(idempotencyKey ? { idempotencyKey } : {}),
            },
          });
          await tx.supportTicket.update({
            where: { id: ticketId },
            data: {
              status: SupportTicketStatus.OPEN,
              lastMessage: this.previewText(createdMessage.text),
              unreadForAdmin: false,
              unreadForUser: true,
            },
          });
          return createdMessage;
        });
        created = true;
      } catch (error) {
        if (
          !(error instanceof Prisma.PrismaClientKnownRequestError) ||
          error.code !== 'P2002' ||
          !idempotencyKey
        ) throw error;
        message = await findExisting();
        if (!message) throw error;
      }
    }
    if (!message) throw new ConflictException('Не удалось подтвердить сообщение');
    if (!created) {
      return { source: 'timeweb', item: this.serializeMessage(message) };
    }

    if (ticket.userId) {
      try {
        await this.notificationsService.createSystemNotification({
          userId: ticket.userId,
          title: 'Ответ поддержки',
          body: this.notificationPreview(message.text),
          type: NotificationType.SUPPORT,
          payload: {
            type: 'support_message',
            actionType: 'support_reply',
            ticketId,
            userId: ticket.userId,
            messageId: message.id,
          },
        });
      } catch {
        // Notification delivery is independent from the committed message.
      }
    }
    this.emitSupportChanged({
      ticketId,
      userId: ticket.userId,
      messageId: message.id,
      action: 'created',
    });

    return {
      source: 'timeweb',
      item: this.serializeMessage(message),
    };
  }

  async createPublicAccessTicket(params: CreatePublicSupportTicketDto) {
    const token = randomBytes(32).toString('base64url');
    const text = this.plainText(params.text, 2000);
    const name = this.plainText(params.name || 'Пользователь', 120);
    const phone = this.plainText(params.oldPhone, 32);
    const email = params.contactEmail?.trim().toLowerCase() || null;
    const ticket = await this.prisma.supportTicket.create({
      data: {
        userId: null,
        category: SupportTicketCategory.ACCESS_RECOVERY,
        publicTokenHash: this.publicTokenHash(token),
        contactPhone: phone,
        contactEmail: email,
        name,
        subject: 'Восстановление доступа',
        status: SupportTicketStatus.OPEN,
        lastMessage: text,
        unreadForAdmin: true,
        messages: { create: { sender: SupportSenderType.USER, text } },
      },
      include: { messages: { orderBy: this.supportMessageOrder() } },
    });
    this.adminDashboardSignal?.changed('support');
    await this.notifyAdminsOfSupport({
      ticketId: ticket.id,
      eventId: ticket.id,
      isNewTicket: true,
    });
    return { source: 'timeweb', publicToken: token, ticket: this.serializeTicket(ticket), items: ticket.messages.map((item) => this.serializeMessage(item)) };
  }

  async getPublicTicket(ticketId: string, token: string) {
    const ticket = await this.findPublicTicket(ticketId, token, true);
    return { source: 'timeweb', ticket: this.serializeTicket(ticket), items: ticket.messages.map((item: any) => this.serializeMessage(item)) };
  }

  async sendPublicMessage(ticketId: string, token: string, rawText: string) {
    const ticket = await this.findPublicTicket(ticketId, token, false);
    if (ticket.status === SupportTicketStatus.CLOSED) throw new BadRequestException('Обращение закрыто');
    const text = this.plainText(rawText, 2000);
    const message = await this.prisma.supportMessage.create({ data: { ticketId, sender: SupportSenderType.USER, text } });
    await this.prisma.supportTicket.update({ where: { id: ticketId }, data: { lastMessage: text, unreadForAdmin: true, unreadForUser: false, status: SupportTicketStatus.OPEN } });
    this.adminDashboardSignal?.changed('support');
    await this.notifyAdminsOfSupport({
      ticketId,
      eventId: message.id,
      isNewTicket: false,
    });
    return { source: 'timeweb', item: this.serializeMessage(message) };
  }

  private async findPublicTicket(ticketId: string, token: string, includeMessages: boolean): Promise<any> {
    const hash = this.publicTokenHash(token);
    const ticket = await this.prisma.supportTicket.findFirst({
      where: { id: ticketId, category: SupportTicketCategory.ACCESS_RECOVERY, publicTokenHash: hash },
      ...(includeMessages ? { include: { messages: { orderBy: this.supportMessageOrder() } } } : {}),
    });
    if (!ticket) throw new NotFoundException('Support ticket not found');
    return ticket;
  }

  private publicTokenHash(token: string) { return createHash('sha256').update(token).digest('hex'); }
  private plainText(value: string, max: number) { return value.replace(/<[^>]*>/g, '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').trim().slice(0, max); }

  async markMessageReadByUser(
    authUser: AuthenticatedUser,
    ticketId: string,
    messageId: string,
  ) {
    const ticket = await this.prisma.supportTicket.findFirst({
      where: { id: ticketId, userId: authUser.userId },
    });
    if (!ticket) throw new NotFoundException('Support ticket not found');

    const result = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`
        SELECT pg_advisory_xact_lock(hashtext(${`support_ticket_read:${ticketId}`}))
      `;
      const message = await tx.supportMessage.findFirst({
        where: {
          id: messageId,
          ticketId,
          sender: SupportSenderType.ADMIN,
          deletedAt: null,
        },
      });
      if (!message) throw new NotFoundException('Support message not found');
      const changed = message.readAt == null;
      const readMessage = changed
        ? await tx.supportMessage.update({
            where: { id: messageId },
            data: { readAt: new Date() },
          })
        : message;
          const unreadCount = await tx.supportMessage.count({
            where: {
              ticketId,
              sender: SupportSenderType.ADMIN,
              readAt: null,
              deletedAt: null,
            },
          });
      await tx.supportTicket.update({
        where: { id: ticketId },
        data: { unreadForUser: unreadCount > 0 },
      });
      return { message: readMessage, changed };
    });
    if (result.changed) {
      this.emitSupportChanged({
        ticketId,
        userId: ticket.userId,
        messageId,
        action: 'read',
      });
    }
    return { source: 'timeweb', item: this.serializeMessage(result.message) };
  }

  async editMessageAsAdmin(
    authUser: AuthenticatedUser,
    ticketId: string,
    messageId: string,
    rawText: string,
  ) {
    const text = rawText.trim();
    if (!text) throw new BadRequestException('Сообщение обязательно');
    const result = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`
        SELECT pg_advisory_xact_lock(hashtext(${`support_message_mutation:${messageId}`}))
      `;
      const message = await tx.supportMessage.findFirst({
        where: { id: messageId, ticketId },
      });
      if (!message ||
          message.sender !== SupportSenderType.ADMIN ||
          message.senderUserId !== authUser.userId ||
          message.deletedAt) {
        throw new NotFoundException('Support message not found');
      }
      const previousContent = this.decodeContent(message.text);
      const encodedText = this.encodeContent({
        text,
        imageUrl: previousContent.imageUrl,
      });
      await tx.supportMessageRevision.create({
        data: {
          messageId,
          editorUserId: authUser.userId,
          previousText: message.text,
        },
      });
      const updated = await tx.supportMessage.update({
        where: { id: messageId },
        data: {
          text: encodedText,
          editedAt: new Date(),
          editedByUserId: authUser.userId,
        },
      });
      const latest = await tx.supportMessage.findFirst({
        where: { ticketId, deletedAt: null },
        orderBy: this.supportMessageOrder(),
      });
      if (latest) {
        await tx.supportTicket.update({
          where: { id: ticketId },
          data: { lastMessage: this.previewText(latest.text) },
        });
      }
      return updated;
    });
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id: ticketId } });
    this.emitSupportChanged({
      ticketId,
      userId: ticket?.userId ?? null,
      messageId,
      action: 'updated',
    });
    return { source: 'timeweb', item: this.serializeMessage(result) };
  }

  async deleteMessageAsAdmin(
    authUser: AuthenticatedUser,
    ticketId: string,
    messageId: string,
  ) {
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`
        SELECT pg_advisory_xact_lock(hashtext(${`support_message_mutation:${messageId}`}))
      `;
      const message = await tx.supportMessage.findFirst({
        where: { id: messageId, ticketId },
      });
      if (!message ||
          message.sender !== SupportSenderType.ADMIN ||
          message.senderUserId !== authUser.userId ||
          message.deletedAt) {
        throw new NotFoundException('Support message not found');
      }
      await tx.supportMessageRevision.create({
        data: {
          messageId,
          editorUserId: authUser.userId,
          previousText: message.text,
        },
      });
      const deleted = await tx.supportMessage.update({
        where: { id: messageId },
        data: {
          deletedAt: new Date(),
          deletedByUserId: authUser.userId,
        },
      });
      const latest = await tx.supportMessage.findFirst({
        where: { ticketId, deletedAt: null },
        orderBy: this.supportMessageOrder(),
      });
      await tx.supportTicket.update({
        where: { id: ticketId },
        data: { lastMessage: latest ? this.previewText(latest.text) : '' },
      });
      return deleted;
    });
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id: ticketId } });
    this.emitSupportChanged({
      ticketId,
      userId: ticket?.userId ?? null,
      messageId,
      action: 'deleted',
    });
    return { source: 'timeweb', item: this.serializeMessage(updated) };
  }

  async closeTicketForUser(authUser: AuthenticatedUser, ticketId: string) {
    const ticket = await this.prisma.supportTicket.findFirst({
      where: {
        id: ticketId,
        userId: authUser.userId,
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    const updated = await this.prisma.supportTicket.update({
      where: {
        id: ticketId,
      },
      data: {
        status: SupportTicketStatus.CLOSED,
        unreadForAdmin: false,
        unreadForUser: false,
      },
    });

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(updated),
    };
  }

  async closeTicketForAdmin(ticketId: string) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: {
        id: ticketId,
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    const updated = await this.prisma.supportTicket.update({
      where: {
        id: ticketId,
      },
      data: {
        status: SupportTicketStatus.CLOSED,
        unreadForAdmin: false,
        unreadForUser: false,
      },
    });

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(updated),
    };
  }

  async markReadByAdmin(ticketId: string) {
    const ticket = await this.prisma.supportTicket.update({
      where: {
        id: ticketId,
      },
      data: {
        unreadForAdmin: false,
      },
    });
    this.adminDashboardSignal?.changed('support');

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(ticket),
    };
  }
}
