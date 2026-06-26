import { IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class CreateReportDto {
  @IsUUID()
  listingId!: string;

  @IsUUID()
  listingOwnerId!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(120)
  reason!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;
}
