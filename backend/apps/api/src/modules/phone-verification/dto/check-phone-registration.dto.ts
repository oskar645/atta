import { IsString } from 'class-validator';

export class CheckPhoneRegistrationDto {
  @IsString()
  phone!: string;
}
