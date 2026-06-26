import { IsIn, IsString } from 'class-validator';

export class StartPhoneVerificationDto {
  @IsString()
  phone!: string;

  @IsIn(['signup', 'login', 'reset_password'])
  purpose!: 'signup' | 'login' | 'reset_password';
}
