import { IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class SendChatMessageDto {
  @IsOptional()
  @IsString()
  @IsUUID()
  chatId?: string;

  @IsOptional()
  @IsString()
  @IsUUID()
  clientMessageId?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  text!: string;
}
