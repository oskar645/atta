import { IsOptional, IsString } from 'class-validator';

export class LoginPhoneDto {
  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  password?: string;

  @IsOptional()
  @IsString()
  verificationCheckId?: string;

  @IsOptional()
  @IsString()
  verification_check_id?: string;
}
