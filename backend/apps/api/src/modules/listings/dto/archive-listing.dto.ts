import { IsIn, IsOptional, IsString } from 'class-validator';

const archiveStatuses = ['sold', 'archived'] as const;

export class ArchiveListingDto {
  @IsOptional()
  @IsIn(archiveStatuses)
  status?: (typeof archiveStatuses)[number];

  @IsOptional()
  @IsString()
  note?: string;
}
