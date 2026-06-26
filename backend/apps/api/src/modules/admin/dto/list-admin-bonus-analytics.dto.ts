import { IsIn, IsOptional, IsString } from 'class-validator';

const analyticsPeriods = ['day', 'week', 'month'] as const;

export class ListAdminBonusAnalyticsDto {
  @IsOptional()
  @IsIn(analyticsPeriods)
  period?: (typeof analyticsPeriods)[number];

  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;
}
