import { IsOptional, IsString, MinLength } from 'class-validator';

export class SignupPhoneDto {
  @IsString()
  phone!: string;

  @IsString()
  @MinLength(8)
  password!: string;

  @IsOptional()
  @IsString()
  displayName?: string;

  @IsOptional()
  @IsString()
  display_name?: string;

  @IsOptional()
  @IsString()
  verificationCheckId?: string;

  @IsOptional()
  @IsString()
  verification_check_id?: string;
}
