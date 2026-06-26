import { IsOptional, IsString } from 'class-validator';

export class ModerateListingDto {
  @IsOptional()
  @IsString()
  reason?: string;

  @IsOptional()
  @IsString()
  moderation_note?: string;
}
