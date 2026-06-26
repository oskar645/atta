import { IsString, IsUUID } from 'class-validator';

export class ChatMessageActionDto {
  @IsString()
  @IsUUID()
  messageId!: string;
}
