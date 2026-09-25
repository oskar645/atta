import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreatePublicSupportTicketDto {
  @IsString()
  @MaxLength(32)
  oldPhone!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  contactEmail?: string;

  @IsString()
  @MinLength(10)
  @MaxLength(2000)
  text!: string;
}

export class PublicSupportMessageDto {
  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  text!: string;
}
