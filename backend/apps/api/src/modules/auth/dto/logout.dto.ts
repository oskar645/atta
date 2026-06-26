import { IsOptional, IsString, MinLength } from 'class-validator';

export class LogoutDto {
  @IsOptional()
  @IsString()
  @MinLength(10)
  refreshToken?: string;
}
