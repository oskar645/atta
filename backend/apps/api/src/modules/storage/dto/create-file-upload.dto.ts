import { IsOptional, IsString } from 'class-validator';

export class CreateFileUploadDto {
  @IsString()
  fileName!: string;

  @IsOptional()
  @IsString()
  contentType?: string;
}
