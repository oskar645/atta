import { IsOptional, IsString, MinLength } from 'class-validator';

export class ResetPasswordPhoneDto {
  @IsString()
  phone!: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  newPassword?: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  new_password?: string;

  @IsOptional()
  @IsString()
  verificationCheckId?: string;

  @IsOptional()
  @IsString()
  verification_check_id?: string;
}
