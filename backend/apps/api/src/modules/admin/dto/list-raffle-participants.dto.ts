import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, ValidateIf } from 'class-validator';
import { Type } from 'class-transformer';

export class ListRaffleParticipantsDto {
  @ValidateIf((value) => !value.snapshotId)
  @IsString()
  @IsDateString({ strict: true })
  @MaxLength(40)
  from?: string;

  @ValidateIf((value) => !value.snapshotId)
  @IsString()
  @IsDateString({ strict: true })
  @MaxLength(40)
  to?: string;

  @ValidateIf((value) => !value.snapshotId)
  @IsString()
  @Matches(/^[1-9][0-9]*$/)
  @MaxLength(12)
  ticketPrice?: string;

  @IsOptional()
  @IsUUID()
  snapshotId?: string;

  @IsOptional()
  @IsString()
  @Matches(/^\d{1,30}$/)
  fromTicket?: string;

  @IsOptional()
  @IsString()
  @Matches(/^\d{1,30}$/)
  toTicket?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  @Type(() => Number)
  limit?: number;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  cursor?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  search?: string;

  // The export endpoint uses the same range contract. Declaring format here is
  // required because the global ValidationPipe forbids unknown query fields.
  @IsOptional()
  @IsIn(['participants', 'tickets'])
  format?: 'participants' | 'tickets';
}
