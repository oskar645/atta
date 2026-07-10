import { IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class CreateReportDto {
  @IsOptional()
  @IsUUID()
  listingId?: string;

  @IsOptional()
  @IsUUID()
  listingOwnerId?: string;

  @IsOptional()
  @IsUUID()
  reportedUserId?: string;

  @IsString()
  @MinLength(2)
  @MaxLength(120)
  reason!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;
}
