"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var SupportService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupportService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
const serializers_1 = require("../../common/serializers");
let SupportService = SupportService_1 = class SupportService {
    constructor(prisma, notificationsService, storageService) {
        this.prisma = prisma;
        this.notificationsService = notificationsService;
        this.storageService = storageService;
    }
    decodeContent(rawText) {
        const text = rawText?.trim() ?? '';
        if (!text.startsWith(SupportService_1.contentPrefix)) {
            return {
                text,
                imageUrl: '',
            };
        }
        try {
            const payload = JSON.parse(text.slice(SupportService_1.contentPrefix.length));
            return {
                text: payload.text?.trim() ?? '',
                imageUrl: payload.image_url?.trim() ?? '',
            };
        }
        catch {
            return {
                text,
                imageUrl: '',
            };
        }
    }
    encodeContent(params) {
        const text = params.text?.trim() ?? '';
        const imageUrl = params.imageUrl?.trim() ?? '';
        if (imageUrl.length === 0) {
            return text;
        }
        return `${SupportService_1.contentPrefix}${JSON.stringify({
            text,
            image_url: imageUrl,
        })}`;
    }
    previewText(rawText) {
        const content = this.decodeContent(rawText);
        if (content.imageUrl.length === 0) {
            return content.text;
        }
        if (content.text.length === 0) {
            return 'Фото';
        }
        return `${content.text} · Фото`;
    }
    notificationPreview(rawText) {
        const preview = this.previewText(rawText).replace(/\s+/g, ' ').trim();
        if (preview.length <= 120)
            return preview;
        return `${preview.slice(0, 117).trim()}...`;
    }
    adminContactIdempotencyKey(userId, rawKey) {
        const key = rawKey?.trim() ?? '';
        if (!key) {
            return null;
        }
        return `support_admin_contact:${userId}:${key}`;
    }
    serializeMessage(message) {
        const content = this.decodeContent(message.text);
        return {
            id: message.id,
            ticket_id: message.ticketId,
            sender: message.sender.toLowerCase(),
            text: content.text,
            image_url: (0, serializers_1.normalizeStoredMediaUrl)(content.imageUrl, {
                category: 'support',
            }) || null,
            sender_user_id: message.senderUserId ?? null,
            created_at: message.createdAt.toISOString(),
        };
    }
    serializeTicket(ticket) {
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
            initiated_by: firstSender == null ? null : firstSender.toString().toLowerCase(),
            created_at: ticket.createdAt.toISOString(),
            updated_at: ticket.updatedAt.toISOString(),
        };
    }
    requireImage(file, maxSizeBytes) {
        if (!file || !file.buffer || file.size === 0) {
            throw new common_1.BadRequestException('Изображение обязательно');
        }
        const mime = file.mimetype.trim().toLowerCase();
        const allowed = new Set(['image/jpeg', 'image/png', 'image/webp']);
        if (!allowed.has(mime)) {
            throw new common_1.BadRequestException('Поддерживаются JPG, PNG и WEBP');
        }
        if (file.size > maxSizeBytes) {
            throw new common_1.BadRequestException('Файл слишком большой');
        }
        return file;
    }
    async uploadImage(authUser, file, ticketId) {
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
            url: (0, serializers_1.normalizeStoredMediaUrl)(media.url, {
                category: 'support',
                providerHint: media.provider,
                storageKey: media.key,
            }),
        };
    }
    async listMyTickets(authUser) {
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
    async openTicketForAdminContact(params) {
        const userId = params.userId?.trim() ?? '';
        const subject = params.subject?.trim() || 'Обращение в поддержку';
        const text = params.text?.trim() ?? '';
        if (!userId) {
            throw new common_1.BadRequestException('Не указан пользователь');
        }
        if (!text) {
            throw new common_1.BadRequestException('Сообщение обязательно');
        }
        const idempotencyKey = this.adminContactIdempotencyKey(userId, params.idempotencyKey);
        const user = await this.prisma.user.findUnique({
            where: {
                id: userId,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('Пользователь не найден');
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
        const name = params.name?.trim() ||
            user.displayName?.trim() ||
            user.name?.trim() ||
            'Пользователь';
        const encodedText = this.encodeContent({ text });
        const preview = this.previewText(encodedText);
        let result;
        try {
            result = await this.prisma.$transaction(async (tx) => {
                await tx.$executeRaw `
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
                        status: client_1.SupportTicketStatus.OPEN,
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
                            status: client_1.SupportTicketStatus.OPEN,
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
                        sender: client_1.SupportSenderType.ADMIN,
                        text: encodedText,
                        ...(idempotencyKey ? { idempotencyKey } : {}),
                    },
                });
                const updatedTicket = await tx.supportTicket.update({
                    where: {
                        id: ticket.id,
                    },
                    data: {
                        status: client_1.SupportTicketStatus.OPEN,
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
        }
        catch (error) {
            if (error instanceof client_1.Prisma.PrismaClientKnownRequestError &&
                error.code === 'P2002') {
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
                }
                else {
                    throw error;
                }
            }
            else {
                throw error;
            }
        }
        if (result.messageCreated) {
            await this.notificationsService.createSystemNotification({
                userId,
                title: 'Сообщение от администрации',
                body: this.notificationPreview(encodedText),
                type: client_1.NotificationType.SUPPORT,
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
    async getTicketForUser(authUser, ticketId) {
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
            throw new common_1.NotFoundException('Support ticket not found');
        }
        return {
            source: 'timeweb',
            ticket: this.serializeTicket(ticket),
            items: ticket.messages.map((message) => this.serializeMessage(message)),
        };
    }
    async getTicketForAdmin(ticketId) {
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
            throw new common_1.NotFoundException('Support ticket not found');
        }
        return {
            source: 'timeweb',
            ticket: this.serializeTicket(ticket),
            items: ticket.messages.map((message) => this.serializeMessage(message)),
        };
    }
    async createTicket(authUser, params) {
        const text = params.text?.trim() ?? '';
        const imageUrl = params.imageUrl?.trim() ?? '';
        if (text.length === 0 && imageUrl.length === 0) {
            throw new common_1.BadRequestException('Сообщение или фото обязательны');
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
                status: client_1.SupportTicketStatus.OPEN,
                lastMessage: firstPreview,
                unreadForAdmin: true,
                unreadForUser: false,
                messages: {
                    create: [
                        {
                            sender: client_1.SupportSenderType.USER,
                            senderUserId: authUser.userId,
                            text: encodedText,
                        },
                        {
                            sender: client_1.SupportSenderType.ADMIN,
                            text: 'Здравствуйте! Мы получили ваше обращение и уже передали его модераторам. Обычно ответ приходит в ближайшее время.',
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
    async createBlockAppeal(authUser, params) {
        const text = params.text?.trim() ?? '';
        const imageUrl = params.imageUrl?.trim() ?? '';
        if (text.length === 0 && imageUrl.length === 0) {
            throw new common_1.BadRequestException('Сообщение или фото обязательны');
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
            throw new common_1.BadRequestException('Активная блокировка не найдена');
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
            ].filter((line) => line != null).join('\n'),
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
                name: user?.displayName?.trim() ||
                    user?.name?.trim() ||
                    user?.phone?.trim() ||
                    'Пользователь',
                subject: 'Апелляция по блокировке',
                status: client_1.SupportTicketStatus.OPEN,
                lastMessage: preview,
                unreadForAdmin: true,
                unreadForUser: false,
                messages: {
                    create: [
                        {
                            sender: client_1.SupportSenderType.USER,
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
    async sendMessageAsUser(authUser, ticketId, text, imageUrl) {
        const normalizedText = text?.trim() ?? '';
        const normalizedImageUrl = imageUrl?.trim() ?? '';
        if (normalizedText.length === 0 && normalizedImageUrl.length === 0) {
            throw new common_1.BadRequestException('Сообщение или фото обязательны');
        }
        const ticket = await this.prisma.supportTicket.findFirst({
            where: {
                id: ticketId,
                userId: authUser.userId,
            },
        });
        if (!ticket) {
            throw new common_1.NotFoundException('Support ticket not found');
        }
        const message = await this.prisma.supportMessage.create({
            data: {
                ticketId,
                sender: client_1.SupportSenderType.USER,
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
                status: client_1.SupportTicketStatus.OPEN,
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
    async sendMessageAsAdmin(ticketId, text, imageUrl) {
        const normalizedText = text?.trim() ?? '';
        const normalizedImageUrl = imageUrl?.trim() ?? '';
        if (normalizedText.length === 0 && normalizedImageUrl.length === 0) {
            throw new common_1.BadRequestException('Сообщение или фото обязательны');
        }
        const ticket = await this.prisma.supportTicket.findUnique({
            where: {
                id: ticketId,
            },
        });
        if (!ticket) {
            throw new common_1.NotFoundException('Support ticket not found');
        }
        const message = await this.prisma.supportMessage.create({
            data: {
                ticketId,
                sender: client_1.SupportSenderType.ADMIN,
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
                status: client_1.SupportTicketStatus.OPEN,
                lastMessage: previewText,
                unreadForAdmin: false,
                unreadForUser: true,
            },
        });
        await this.notificationsService.createSystemNotification({
            userId: ticket.userId,
            title: 'Ответ поддержки',
            body: this.notificationPreview(message.text),
            type: client_1.NotificationType.SUPPORT,
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
    async closeTicketForUser(authUser, ticketId) {
        const ticket = await this.prisma.supportTicket.findFirst({
            where: {
                id: ticketId,
                userId: authUser.userId,
            },
        });
        if (!ticket) {
            throw new common_1.NotFoundException('Support ticket not found');
        }
        const updated = await this.prisma.supportTicket.update({
            where: {
                id: ticketId,
            },
            data: {
                status: client_1.SupportTicketStatus.CLOSED,
                unreadForAdmin: false,
                unreadForUser: false,
            },
        });
        return {
            source: 'timeweb',
            ticket: this.serializeTicket(updated),
        };
    }
    async closeTicketForAdmin(ticketId) {
        const ticket = await this.prisma.supportTicket.findUnique({
            where: {
                id: ticketId,
            },
        });
        if (!ticket) {
            throw new common_1.NotFoundException('Support ticket not found');
        }
        const updated = await this.prisma.supportTicket.update({
            where: {
                id: ticketId,
            },
            data: {
                status: client_1.SupportTicketStatus.CLOSED,
                unreadForAdmin: false,
                unreadForUser: false,
            },
        });
        return {
            source: 'timeweb',
            ticket: this.serializeTicket(updated),
        };
    }
    async markReadByAdmin(ticketId) {
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
};
exports.SupportService = SupportService;
SupportService.contentPrefix = '__atta_support_payload__:';
exports.SupportService = SupportService = SupportService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        notifications_service_1.NotificationsService,
        storage_service_1.StorageService])
], SupportService);
//# sourceMappingURL=support.service.js.map