import { IsString, MaxLength, MinLength } from 'class-validator';

export class UpdateSupportMessageDto {
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  text!: string;
}
