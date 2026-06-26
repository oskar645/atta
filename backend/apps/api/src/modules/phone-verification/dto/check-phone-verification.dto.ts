import { IsIn, IsOptional, IsString } from 'class-validator';

export class CheckPhoneVerificationDto {
  @IsString()
  phone!: string;

  @IsString()
  @IsOptional()
  checkId?: string;

  @IsString()
  @IsOptional()
  verificationId?: string;

  @IsIn(['signup', 'login', 'reset_password'])
  purpose!: 'signup' | 'login' | 'reset_password';
}
