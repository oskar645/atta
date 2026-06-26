import { IsIn, IsString } from 'class-validator';

const promotionTypes = ['showcase', 'bump', 'vip', 'turbo'] as const;

export class CreatePromotionDto {
  @IsString()
  @IsIn(promotionTypes)
  type!: (typeof promotionTypes)[number];
}
