import { IsString, MaxLength, MinLength } from 'class-validator';

export class SendAdminSupportMessageDto {
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  message!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(160)
  idempotencyKey!: string;
}
