import { IsEmail, IsString, IsUUID, Matches, MaxLength } from 'class-validator';

export class StartRecoveryEmailDto {
  @IsEmail()
  @MaxLength(254)
  email!: string;
}

export class VerifyEmailCodeDto {
  @IsUUID()
  challengeId!: string;

  @Matches(/^\d{6}$/)
  code!: string;
}

export class RecoveryGrantDto {
  @IsString()
  @MaxLength(256)
  recoveryToken!: string;
}

export class StartRecoveryPhoneDto extends RecoveryGrantDto {
  @IsString()
  @MaxLength(32)
  phone!: string;
}

export class CompleteRecoveryPhoneDto extends StartRecoveryPhoneDto {
  @IsString()
  @MaxLength(128)
  verificationCheckId!: string;
}
