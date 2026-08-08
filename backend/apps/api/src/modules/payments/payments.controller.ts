import { Body, Controller, Get, Header, Param, Post, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateYookassaPaymentDto } from './dto/create-yookassa-payment.dto';
import { PaymentsService } from './payments.service';

@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post('yookassa/create')
  @UseGuards(JwtAuthGuard)
  createYookassaPayment(
    @CurrentUser() authUser: AuthenticatedUser,
    @Body() body: CreateYookassaPaymentDto,
  ) {
    return this.paymentsService.createYookassaPayment(authUser, body.amountRub);
  }

  @Post('yookassa/webhook')
  handleYookassaWebhook(@Body() body: unknown) {
    return this.paymentsService.handleYookassaWebhook(body);
  }

  @Get('yookassa/return')
  @Header('Content-Type', 'text/html; charset=utf-8')
  getYookassaReturnPage() {
    return this.paymentsService.renderYookassaReturnPage();
  }

  @Get(':id/status')
  @UseGuards(JwtAuthGuard)
  getPaymentStatus(
    @CurrentUser() authUser: AuthenticatedUser,
    @Param('id') paymentId: string,
  ) {
    return this.paymentsService.getPaymentStatus(authUser, paymentId);
  }
}
