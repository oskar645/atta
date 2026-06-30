import { IsOptional, IsString, MinLength } from 'class-validator';

export class SignupPhoneDto {
  @IsString()
  phone!: string;

  @IsString()
  @MinLength(8, {
    message: 'Пароль должен быть не короче 8 символов',
  })
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
