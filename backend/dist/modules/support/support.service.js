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
            orderBy: {
                updatedAt: 'desc',
            },
        });
        return {
            source: 'timeweb',
            items: items.map((ticket) => this.serializeTicket(ticket)),
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
            body: previewText,
            type: client_1.NotificationType.SUPPORT,
            payload: {
                ticketId,
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