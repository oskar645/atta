import { IsIn, IsOptional, IsString } from 'class-validator';

const transactionTypes = ['accrual', 'spend', 'refund', 'all'] as const;

export class ListAdminWalletTransactionsDto {
  @IsOptional()
  @IsIn(transactionTypes)
  type?: (typeof transactionTypes)[number];

  @IsOptional()
  @IsString()
  reason?: string;

  @IsOptional()
  @IsString()
  userId?: string;

  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;
}
