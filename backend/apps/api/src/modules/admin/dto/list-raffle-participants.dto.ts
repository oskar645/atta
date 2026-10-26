import { IsInt, IsOptional, IsString, Matches, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class ListRaffleParticipantsDto {
  @IsString()
  from!: string;

  @IsString()
  to!: string;

  @IsString()
  @Matches(/^[1-9][0-9]*$/)
  ticketPrice!: string;

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
