import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  NotificationType,
  Prisma,
  SupportSenderType,
  SupportTicketStatus,
} from '@prisma/client';

import { AuthenticatedUser } from '../auth/auth.types';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UploadedImageFile } from '../storage/uploaded-image-file.type';
import { normalizeStoredMediaUrl } from '../../common/serializers';

@Injectable()
export class SupportService {
  private static readonly contentPrefix = '__atta_support_payload__:';

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
    private readonly storageService: StorageService,
  ) {}

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
  }) {
    const content = this.decodeContent(message.text);
    return {
      id: message.id,
      ticket_id: message.ticketId,
      sender: message.sender.toLowerCase(),
      text: content.text,
      image_url:
        normalizeStoredMediaUrl(content.imageUrl, {
          category: 'support',
        }) || null,
      sender_user_id: message.senderUserId ?? null,
      created_at: message.createdAt.toISOString(),
    };
  }

  private serializeTicket(ticket: {
    id: string;
    userId: string;
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

  async listTickets() {
    const items = await this.prisma.supportTicket.findMany({
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
    }

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
          orderBy: {
            createdAt: 'desc',
          },
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
          orderBy: {
            createdAt: 'desc',
          },
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
    params: { name?: string; subject?: string; text?: string; imageUrl?: string },
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

    const ticket = await this.prisma.supportTicket.create({
      data: {
        userId: authUser.userId,
        name,
        subject,
        status: SupportTicketStatus.OPEN,
        lastMessage: firstPreview,
        unreadForAdmin: true,
        unreadForUser: false,
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
      include: {
        messages: {
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
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
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
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
  ) {
    const normalizedText = text?.trim() ?? '';
    const normalizedImageUrl = imageUrl?.trim() ?? '';
    if (normalizedText.length === 0 && normalizedImageUrl.length === 0) {
      throw new BadRequestException('Сообщение или фото обязательны');
    }
    const ticket = await this.prisma.supportTicket.findFirst({
      where: {
        id: ticketId,
        userId: authUser.userId,
      },
    });

    if (!ticket) {
      throw new NotFoundException('Support ticket not found');
    }

    const message = await this.prisma.supportMessage.create({
      data: {
        ticketId,
        sender: SupportSenderType.USER,
        senderUserId: authUser.userId,
        text: this.encodeContent({
          text: normalizedText,
          imageUrl: normalizedImageUrl,
        }),
      },
    });

    const previewText = this.previewText(message.text);

    await this.prisma.supportTicket.update({
      where: {
        id: ticketId,
      },
      data: {
        status: SupportTicketStatus.OPEN,
        lastMessage: previewText,
        unreadForAdmin: true,
        unreadForUser: false,
      },
    });

    return {
      source: 'timeweb',
      item: this.serializeMessage(message),
    };
  }

  async sendMessageAsAdmin(ticketId: string, text?: string, imageUrl?: string) {
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

    const message = await this.prisma.supportMessage.create({
      data: {
        ticketId,
        sender: SupportSenderType.ADMIN,
        text: this.encodeContent({
          text: normalizedText,
          imageUrl: normalizedImageUrl,
        }),
      },
    });

    const previewText = this.previewText(message.text);

    await this.prisma.supportTicket.update({
      where: {
        id: ticketId,
      },
      data: {
        status: SupportTicketStatus.OPEN,
        lastMessage: previewText,
        unreadForAdmin: false,
        unreadForUser: true,
      },
    });

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

    return {
      source: 'timeweb',
      item: this.serializeMessage(message),
    };
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

    return {
      source: 'timeweb',
      ticket: this.serializeTicket(ticket),
    };
  }
}
