import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';

export class SignupDto {
  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  displayName?: string;

  @IsOptional()
  @IsString()
  display_name?: string;

  @IsString()
  @MinLength(8, {
    message: 'Пароль должен быть не короче 8 символов',
  })
  password!: string;
}
