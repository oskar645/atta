import { Type } from 'class-transformer';
import { IsBoolean, IsInt, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';

export class RecordSearchAttemptDto {
  @IsUUID('4')
  attemptId!: string;

  @IsString()
  @MaxLength(240)
  query!: string;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1000000000)
  resultCount!: number;

  @IsBoolean()
  hasRestrictiveFilters!: boolean;
}
