import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export class ModerateReportDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;

  @IsOptional()
  @IsIn(['resolved', 'no_violation', 'warned', 'removed', 'action_taken'])
  decision?: string;
}
