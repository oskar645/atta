import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import nodemailer, { SentMessageInfo, Transporter } from 'nodemailer';

import { env } from '../../config/env';

@Injectable()
export class EmailService {
  private readonly transporter: Transporter | null;

  constructor() {
    this.transporter = this.isConfigured()
      ? nodemailer.createTransport({
          host: env.SMTP_HOST,
          port: env.SMTP_PORT,
          secure: env.SMTP_SECURE,
          auth: { user: env.SMTP_USER, pass: env.SMTP_PASS },
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
      throw new HttpException(
        { code: 'EMAIL_UNAVAILABLE', message: 'Отправка email временно недоступна' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }

  async sendVerificationCode(params: { to: string; code: string }) {
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
    return this.transporter!.verify();
  }

  async sendRecoveryCompleted(params: { to: string }) {
    await this.send({
      to: params.to,
      subject: 'Номер телефона аккаунта ATTA изменён',
      text: 'ATTA\n\nНомер телефона вашего аккаунта ATTA был изменён.\n\nЕсли это были не вы, обратитесь в поддержку ATTA.',
      html: this.template('Номер телефона изменён', '<p>Номер телефона вашего аккаунта ATTA был изменён.</p><p style="color:#667085">Если это были не вы, обратитесь в поддержку ATTA.</p>'),
    });
  }

  async sendRecoveryEmailChanged(params: { to: string }) {
    await this.send({
      to: params.to,
      subject: 'Резервный email аккаунта ATTA изменён',
      text: 'ATTA\n\nРезервный email вашего аккаунта ATTA был изменён.\n\nЕсли это были не вы, обратитесь в поддержку ATTA.',
      html: this.template('Резервный email изменён', '<p>Резервный email вашего аккаунта ATTA был изменён.</p><p style="color:#667085">Если это были не вы, обратитесь в поддержку ATTA.</p>'),
    });
  }

  private async send(message: { to: string; subject: string; text: string; html: string }): Promise<SentMessageInfo> {
    this.ensureAvailable();
    return this.transporter!.sendMail({ from: env.SMTP_FROM, ...message });
  }

  private isConfigured() {
    return Boolean(env.SMTP_HOST && env.SMTP_USER && env.SMTP_PASS && env.SMTP_FROM);
  }

  private formatCode(code: string) {
    return code.replace(/^(\d{3})(\d{3})$/, '$1 $2');
  }

  private template(title: string, body: string) {
    return `<!doctype html><html><body style="margin:0;background:#f6f8fb;font-family:Arial,sans-serif;color:#101828"><div style="max-width:520px;margin:32px auto;background:#fff;border-radius:16px;padding:32px"><div style="font-size:24px;font-weight:800;color:#0f5fff">ATTA</div><h1 style="font-size:22px;margin:28px 0 12px">${title}</h1>${body}</div></body></html>`;
  }
}
