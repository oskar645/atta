import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

const promotionTypes = ['showcase', 'bump', 'vip', 'turbo'] as const;

export class CreatePromotionDto {
  @IsString()
  @IsIn(promotionTypes)
  type!: (typeof promotionTypes)[number];

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(30)
  days?: number;

  @IsOptional()
  @IsString()
  idempotencyKey?: string;
}
