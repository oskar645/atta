import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class SendSupportMessageDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  text?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  image_url?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  imageUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  idempotencyKey?: string;
}
