import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class ListDeletedUsersDto {
  @IsOptional()
  @IsString()
  @IsIn(['today', '7d', 'month', 'all'])
  period?: 'today' | '7d' | 'month' | 'all';

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
