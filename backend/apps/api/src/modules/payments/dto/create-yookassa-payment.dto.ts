import { IsInt, IsPositive } from 'class-validator';

export class CreateYookassaPaymentDto {
  @IsInt()
  @IsPositive()
  amountRub!: number;
}
