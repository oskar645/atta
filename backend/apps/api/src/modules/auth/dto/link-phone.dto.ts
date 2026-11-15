import { IsString } from 'class-validator';

export class StartLinkPhoneDto {
  @IsString()
  phone!: string;
}

export class CompleteLinkPhoneDto {
  @IsString()
  phone!: string;

  @IsString()
  verificationId!: string;
}
