import { IsIn, IsString } from 'class-validator';

export class StartPhoneVerificationDto {
  @IsString()
  phone!: string;

  @IsIn(['signup', 'login', 'reset_password', 'change_phone'])
  purpose!: 'signup' | 'login' | 'reset_password' | 'change_phone';
}
