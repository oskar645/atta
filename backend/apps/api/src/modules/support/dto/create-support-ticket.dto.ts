import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateSupportTicketDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  subject?: string;

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
}
