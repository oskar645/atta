import { IsIn, IsOptional, IsString } from 'class-validator';

const promotionStatuses = ['active', 'expired', 'cancelled', 'all'] as const;
const promotionTypes = ['showcase', 'bump', 'vip', 'turbo', 'all'] as const;

export class ListAdminPromotionsDto {
  @IsOptional()
  @IsIn(promotionStatuses)
  status?: (typeof promotionStatuses)[number];

  @IsOptional()
  @IsIn(promotionTypes)
  type?: (typeof promotionTypes)[number];

  @IsOptional()
  @IsString()
  userId?: string;

  @IsOptional()
  @IsString()
  listingId?: string;

  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;
}
