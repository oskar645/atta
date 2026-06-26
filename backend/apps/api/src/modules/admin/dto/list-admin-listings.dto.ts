import { IsIn, IsOptional, IsString } from 'class-validator';

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
}
