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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmailService = void 0;
const common_1 = require("@nestjs/common");
const nodemailer_1 = __importDefault(require("nodemailer"));
const env_1 = require("../../config/env");
let EmailService = class EmailService {
    constructor() {
        this.transporter = this.isConfigured()
            ? nodemailer_1.default.createTransport({
                host: env_1.env.SMTP_HOST,
                port: env_1.env.SMTP_PORT,
                secure: env_1.env.SMTP_SECURE,
                auth: { user: env_1.env.SMTP_USER, pass: env_1.env.SMTP_PASS },
                // Keep SMTP bounded below the mobile HTTP deadline. Without these,
                // sendMail may accept a message after Flutter has already timed out.
                connectionTimeout: 10_000,
                greetingTimeout: 10_000,
                socketTimeout: 15_000,
            })
            : null;
    }
    ensureAvailable() {
        if (!this.transporter) {
            throw new common_1.HttpException({ code: 'EMAIL_UNAVAILABLE', message: 'Отправка email временно недоступна' }, common_1.HttpStatus.SERVICE_UNAVAILABLE);
        }
    }
    async sendVerificationCode(params) {
        const displayCode = this.formatCode(params.code);
        return this.send({
            to: params.to,
            subject: 'Код подтверждения ATTA',
            text: `ATTA\n\nКод подтверждения\n\n${displayCode}\n\nКод действует 10 минут.\n\nЕсли вы не запрашивали этот код, просто проигнорируйте письмо.\nНикому не сообщайте код.`,
            html: this.template('Код подтверждения', `<div style="font-size:32px;font-weight:700;letter-spacing:8px;margin:24px 0">${displayCode}</div><p>Код действует 10 минут.</p><p style="color:#667085">Если вы не запрашивали этот код, просто проигнорируйте письмо.<br>Никому не сообщайте код.</p>`),
        });
    }
    async verify() {
        this.ensureAvailable();
        return this.transporter.verify();
    }
    async sendRecoveryCompleted(params) {
        await this.send({
            to: params.to,
            subject: 'Номер телефона аккаунта ATTA изменён',
            text: 'ATTA\n\nНомер телефона вашего аккаунта ATTA был изменён.\n\nЕсли это были не вы, обратитесь в поддержку ATTA.',
            html: this.template('Номер телефона изменён', '<p>Номер телефона вашего аккаунта ATTA был изменён.</p><p style="color:#667085">Если это были не вы, обратитесь в поддержку ATTA.</p>'),
        });
    }
    async sendRecoveryEmailChanged(params) {
        await this.send({
            to: params.to,
            subject: 'Резервный email аккаунта ATTA изменён',
            text: 'ATTA\n\nРезервный email вашего аккаунта ATTA был изменён.\n\nЕсли это были не вы, обратитесь в поддержку ATTA.',
            html: this.template('Резервный email изменён', '<p>Резервный email вашего аккаунта ATTA был изменён.</p><p style="color:#667085">Если это были не вы, обратитесь в поддержку ATTA.</p>'),
        });
    }
    async send(message) {
        this.ensureAvailable();
        return this.transporter.sendMail({ from: env_1.env.SMTP_FROM, ...message });
    }
    isConfigured() {
        return Boolean(env_1.env.SMTP_HOST && env_1.env.SMTP_USER && env_1.env.SMTP_PASS && env_1.env.SMTP_FROM);
    }
    formatCode(code) {
        return code.replace(/^(\d{3})(\d{3})$/, '$1 $2');
    }
    template(title, body) {
        return `<!doctype html><html><body style="margin:0;background:#f6f8fb;font-family:Arial,sans-serif;color:#101828"><div style="max-width:520px;margin:32px auto;background:#fff;border-radius:16px;padding:32px"><div style="font-size:24px;font-weight:800;color:#0f5fff">ATTA</div><h1 style="font-size:22px;margin:28px 0 12px">${title}</h1>${body}</div></body></html>`;
    }
};
exports.EmailService = EmailService;
exports.EmailService = EmailService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [])
], EmailService);
//# sourceMappingURL=email.service.js.map