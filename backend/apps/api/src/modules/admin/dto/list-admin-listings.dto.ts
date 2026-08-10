import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

const listingStatuses = [
  'pending',
  'approved',
  'rejected',
  'sold',
  'deleted',
  'archived',
  'all',
] as const;

export class ListAdminListingsDto {
  @IsOptional()
  @IsString()
  @IsIn(listingStatuses)
  status?: (typeof listingStatuses)[number];

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  @Type(() => Number)
  limit?: number;

  @IsOptional()
  @IsString()
  cursor?: string;
}
