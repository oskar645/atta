import { IsString, IsUUID } from 'class-validator';

export class CreateChatDto {
  @IsString()
  @IsUUID()
  listingId!: string;

  @IsString()
  @IsUUID()
  sellerId!: string;
}
