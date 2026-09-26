import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class AdminAnalyticsPeriodDto {
  @IsOptional()
  @IsIn(['today', '7d', 'month', 'all'])
  period?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  search?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  cursor?: string;

  @IsOptional()
  @IsIn(['oldest', 'newest'])
  sort?: string;
}
