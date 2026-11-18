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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var SupportService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupportService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const crypto_1 = require("crypto");
const notifications_service_1 = require("../notifications/notifications.service");
const prisma_service_1 = require("../prisma/prisma.service");
const storage_service_1 = require("../storage/storage.service");
const serializers_1 = require("../../common/serializers");
const admin_dashboard_signal_1 = require("../../common/admin-dashboard-signal");
const support_realtime_signal_1 = require("../../common/support-realtime-signal");
const image_upload_1 = require("../media/image-upload");
let SupportService = SupportService_1 = class SupportService {
    constructor(prisma, notificationsService, storageService, adminDashboardSignal, supportRealtimeSignal) {
        this.prisma = prisma;
        this.notificationsService = notificationsService;
        this.storageService = storageService;
        this.adminDashboardSignal = adminDashboardSignal;
        this.supportRealtimeSignal = supportRealtimeSignal;
    }
    async notifyAdminsOfSupport(params) {
        try {
            await this.notificationsService.createAdminEventNotifications({
                eventKey: `admin_support:${params.isNewTicket ? 'ticket' : 'message'}:${params.eventId}`,
                title: 'ATTA — Техподдержка',
                body: params.isNewTicket
                    ? 'Поступило новое обращение пользователя.'
                    : 'Новое сообщение в техподдержке.',
                type: client_1.NotificationType.SUPPORT,
                payload: {
                    actionType: 'admin_support_new',
                    ticketId: params.ticketId,
                },
            });
        }
        catch {
            // Administrative delivery must not roll back a completed support write.
        }
    }
    pageLimit(value, fallback = 50) {
        const parsed = Number(value ?? fallback);
        if (!Number.isFinite(parsed))
            return fallback;
        return Math.min(Math.max(Math.trunc(parsed), 1), 100);
    }
    encodeAdminCursor(value) {
        return Buffer.from(JSON.stringify(value)).toString('base64url');
    }
    decodeAdminCursor(cursor) {
        const normalized = cursor?.trim();
        if (!normalized)
            return null;
        try {
            const parsed = JSON.parse(Buffer.from(normalized, 'base64url').toString('utf8'));
            if (!parsed || typeof parsed !== 'object')
                return null;
            return parsed;
        }
        catch {
            return null;
        }
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
        const deleted = message.deletedAt != null;
        return {
            id: message.id,
            ticket_id: message.ticketId,
            sender: message.sender.toLowerCase(),
            text: deleted ? '' : content.text,
            image_url: deleted ? null : (0, serializers_1.normalizeStoredMediaUrl)(content.imageUrl, {
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
    supportMessageOrder() {
        return [{ createdAt: 'desc' }, { id: 'desc' }];
    }
    emitSupportChanged(params) {
        this.supportRealtimeSignal?.changed(params);
    }
    validateIdempotentMessage(message, expected) {
        if (message.ticketId !== expected.ticketId ||
            message.sender !== expected.sender ||
            message.senderUserId !== expected.senderUserId ||
            message.text !== expected.text) {
            throw new common_1.ConflictException('Ключ отправки уже использован для другого сообщения');
        }
    }
    serializeTicket(ticket) {
        const firstSender = ticket.messages?.[0]?.sender;
        return {
            id: ticket.id,
            uid: ticket.userId,
            user_id: ticket.userId,
            category: (ticket.category ?? client_1.SupportTicketCategory.GENERAL).toLowerCase(),
            contact_phone: ticket.contactPhone ?? null,
            contact_email: ticket.contactEmail ?? null,
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
        if ((0, image_upload_1.detectImageMime)(file.buffer) !== mime) {
            throw new common_1.BadRequestException('Файл не является корректным изображением');
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
    async listTickets(query = {}) {
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
            try {
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
            catch {
                // Notification delivery is independent from the committed message.
            }
            this.emitSupportChanged({
                ticketId: result.ticket.id,
                userId,
                messageId: result.message.id,
                action: 'created',
            });
        }
        if (result.ticketCreated)
            this.adminDashboardSignal?.changed('support');
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
                    orderBy: this.supportMessageOrder(),
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
                    orderBy: this.supportMessageOrder(),
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
        const idempotencyKey = params.idempotencyKey?.trim() || null;
        const findExisting = async () => {
            if (!idempotencyKey)
                return null;
            const existing = await this.prisma.supportTicket.findUnique({
                where: { createIdempotencyKey: idempotencyKey },
                include: { messages: { orderBy: this.supportMessageOrder() } },
            });
            if (!existing)
                return null;
            const firstUserMessage = existing.messages
                .slice()
                .reverse()
                .find((message) => message.sender === client_1.SupportSenderType.USER);
            if (existing.userId !== authUser.userId ||
                firstUserMessage?.text !== encodedText) {
                throw new common_1.ConflictException('Ключ отправки уже использован для другого обращения');
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
                        status: client_1.SupportTicketStatus.OPEN,
                        lastMessage: firstPreview,
                        unreadForAdmin: true,
                        unreadForUser: false,
                        ...(idempotencyKey ? { createIdempotencyKey: idempotencyKey } : {}),
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
                    include: { messages: { orderBy: this.supportMessageOrder() } },
                });
                created = true;
            }
            catch (error) {
                if (!(error instanceof client_1.Prisma.PrismaClientKnownRequestError) ||
                    error.code !== 'P2002' ||
                    !idempotencyKey) {
                    throw error;
                }
                ticket = await findExisting();
                if (!ticket)
                    throw error;
            }
        }
        if (!ticket)
            throw new common_1.ConflictException('Не удалось подтвердить обращение');
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
    async sendMessageAsUser(authUser, ticketId, text, imageUrl, rawIdempotencyKey) {
        const normalizedText = text?.trim() ?? '';
        const normalizedImageUrl = imageUrl?.trim() ?? '';
        if (normalizedText.length === 0 && normalizedImageUrl.length === 0) {
            throw new common_1.BadRequestException('Сообщение или фото обязательны');
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
            throw new common_1.NotFoundException('Support ticket not found');
        }
        const expected = {
            ticketId,
            sender: client_1.SupportSenderType.USER,
            senderUserId: authUser.userId,
            text: encodedText,
        };
        const findExisting = async () => {
            if (!idempotencyKey)
                return null;
            const existing = await this.prisma.supportMessage.findUnique({
                where: { idempotencyKey },
            });
            if (existing)
                this.validateIdempotentMessage(existing, expected);
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
                            status: client_1.SupportTicketStatus.OPEN,
                            lastMessage: this.previewText(createdMessage.text),
                            unreadForAdmin: true,
                            unreadForUser: false,
                        },
                    });
                    return createdMessage;
                });
                created = true;
            }
            catch (error) {
                if (!(error instanceof client_1.Prisma.PrismaClientKnownRequestError) ||
                    error.code !== 'P2002' ||
                    !idempotencyKey)
                    throw error;
                message = await findExisting();
                if (!message)
                    throw error;
            }
        }
        if (!message)
            throw new common_1.ConflictException('Не удалось подтвердить сообщение');
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
    async sendMessageAsAdmin(authUser, ticketId, text, imageUrl, rawIdempotencyKey) {
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
        const encodedText = this.encodeContent({
            text: normalizedText,
            imageUrl: normalizedImageUrl,
        });
        const idempotencyKey = rawIdempotencyKey?.trim() || null;
        const expected = {
            ticketId,
            sender: client_1.SupportSenderType.ADMIN,
            senderUserId: authUser.userId,
            text: encodedText,
        };
        const findExisting = async () => {
            if (!idempotencyKey)
                return null;
            const existing = await this.prisma.supportMessage.findUnique({
                where: { idempotencyKey },
            });
            if (existing)
                this.validateIdempotentMessage(existing, expected);
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
                            status: client_1.SupportTicketStatus.OPEN,
                            lastMessage: this.previewText(createdMessage.text),
                            unreadForAdmin: false,
                            unreadForUser: true,
                        },
                    });
                    return createdMessage;
                });
                created = true;
            }
            catch (error) {
                if (!(error instanceof client_1.Prisma.PrismaClientKnownRequestError) ||
                    error.code !== 'P2002' ||
                    !idempotencyKey)
                    throw error;
                message = await findExisting();
                if (!message)
                    throw error;
            }
        }
        if (!message)
            throw new common_1.ConflictException('Не удалось подтвердить сообщение');
        if (!created) {
            return { source: 'timeweb', item: this.serializeMessage(message) };
        }
        if (ticket.userId) {
            try {
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
            }
            catch {
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
    async createPublicAccessTicket(params) {
        const token = (0, crypto_1.randomBytes)(32).toString('base64url');
        const text = this.plainText(params.text, 2000);
        const name = this.plainText(params.name || 'Пользователь', 120);
        const phone = this.plainText(params.oldPhone, 32);
        const email = params.contactEmail?.trim().toLowerCase() || null;
        const ticket = await this.prisma.supportTicket.create({
            data: {
                userId: null,
                category: client_1.SupportTicketCategory.ACCESS_RECOVERY,
                publicTokenHash: this.publicTokenHash(token),
                contactPhone: phone,
                contactEmail: email,
                name,
                subject: 'Восстановление доступа',
                status: client_1.SupportTicketStatus.OPEN,
                lastMessage: text,
                unreadForAdmin: true,
                messages: { create: { sender: client_1.SupportSenderType.USER, text } },
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
    async getPublicTicket(ticketId, token) {
        const ticket = await this.findPublicTicket(ticketId, token, true);
        return { source: 'timeweb', ticket: this.serializeTicket(ticket), items: ticket.messages.map((item) => this.serializeMessage(item)) };
    }
    async sendPublicMessage(ticketId, token, rawText) {
        const ticket = await this.findPublicTicket(ticketId, token, false);
        if (ticket.status === client_1.SupportTicketStatus.CLOSED)
            throw new common_1.BadRequestException('Обращение закрыто');
        const text = this.plainText(rawText, 2000);
        const message = await this.prisma.supportMessage.create({ data: { ticketId, sender: client_1.SupportSenderType.USER, text } });
        await this.prisma.supportTicket.update({ where: { id: ticketId }, data: { lastMessage: text, unreadForAdmin: true, unreadForUser: false, status: client_1.SupportTicketStatus.OPEN } });
        this.adminDashboardSignal?.changed('support');
        await this.notifyAdminsOfSupport({
            ticketId,
            eventId: message.id,
            isNewTicket: false,
        });
        return { source: 'timeweb', item: this.serializeMessage(message) };
    }
    async findPublicTicket(ticketId, token, includeMessages) {
        const hash = this.publicTokenHash(token);
        const ticket = await this.prisma.supportTicket.findFirst({
            where: { id: ticketId, category: client_1.SupportTicketCategory.ACCESS_RECOVERY, publicTokenHash: hash },
            ...(includeMessages ? { include: { messages: { orderBy: this.supportMessageOrder() } } } : {}),
        });
        if (!ticket)
            throw new common_1.NotFoundException('Support ticket not found');
        return ticket;
    }
    publicTokenHash(token) { return (0, crypto_1.createHash)('sha256').update(token).digest('hex'); }
    plainText(value, max) { return value.replace(/<[^>]*>/g, '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').trim().slice(0, max); }
    async markMessageReadByUser(authUser, ticketId, messageId) {
        const ticket = await this.prisma.supportTicket.findFirst({
            where: { id: ticketId, userId: authUser.userId },
        });
        if (!ticket)
            throw new common_1.NotFoundException('Support ticket not found');
        const result = await this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw `
        SELECT pg_advisory_xact_lock(hashtext(${`support_ticket_read:${ticketId}`}))
      `;
            const message = await tx.supportMessage.findFirst({
                where: {
                    id: messageId,
                    ticketId,
                    sender: client_1.SupportSenderType.ADMIN,
                    deletedAt: null,
                },
            });
            if (!message)
                throw new common_1.NotFoundException('Support message not found');
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
                    sender: client_1.SupportSenderType.ADMIN,
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
    async editMessageAsAdmin(authUser, ticketId, messageId, rawText) {
        const text = rawText.trim();
        if (!text)
            throw new common_1.BadRequestException('Сообщение обязательно');
        const result = await this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw `
        SELECT pg_advisory_xact_lock(hashtext(${`support_message_mutation:${messageId}`}))
      `;
            const message = await tx.supportMessage.findFirst({
                where: { id: messageId, ticketId },
            });
            if (!message ||
                message.sender !== client_1.SupportSenderType.ADMIN ||
                message.senderUserId !== authUser.userId ||
                message.deletedAt) {
                throw new common_1.NotFoundException('Support message not found');
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
    async deleteMessageAsAdmin(authUser, ticketId, messageId) {
        const updated = await this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw `
        SELECT pg_advisory_xact_lock(hashtext(${`support_message_mutation:${messageId}`}))
      `;
            const message = await tx.supportMessage.findFirst({
                where: { id: messageId, ticketId },
            });
            if (!message ||
                message.sender !== client_1.SupportSenderType.ADMIN ||
                message.senderUserId !== authUser.userId ||
                message.deletedAt) {
                throw new common_1.NotFoundException('Support message not found');
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
        this.adminDashboardSignal?.changed('support');
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
    __param(3, (0, common_1.Optional)()),
    __param(4, (0, common_1.Optional)()),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        notifications_service_1.NotificationsService,
        storage_service_1.StorageService,
        admin_dashboard_signal_1.AdminDashboardSignal,
        support_realtime_signal_1.SupportRealtimeSignal])
], SupportService);
//# sourceMappingURL=support.service.js.map