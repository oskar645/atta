import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class BlockUserDto {
  @IsString()
  duration!: string;

  @IsString()
  reason!: string;

  @IsOptional()
  @IsString()
  internal_note?: string;

  @IsOptional()
  @IsString()
  listing_id?: string;

  @IsOptional()
  @IsString()
  ends_at?: string;

  @IsOptional()
  @IsBoolean()
  ban_phone_identity?: boolean;
}

export class UnblockUserDto {
  @IsOptional()
  @IsString()
  reason?: string;
}

export class UpdateUserBlockDto {
  @IsOptional()
  @IsString()
  ends_at?: string;

  @IsOptional()
  @IsBoolean()
  permanent?: boolean;

  @IsOptional()
  @IsString()
  internal_note?: string;

  @IsOptional()
  @IsString()
  reason?: string;
}
