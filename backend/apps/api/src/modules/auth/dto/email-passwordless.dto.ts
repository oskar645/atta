import {
  IsBoolean,
  IsEmail,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
} from 'class-validator';

export class StartEmailPasswordlessDto {
  @IsEmail()
  @MaxLength(320)
  email!: string;
}

export class CheckEmailPasswordlessDto {
  @IsString()
  challengeId!: string;

  @IsString()
  @Matches(/^\d{6}$/)
  code!: string;
}

export class CompleteEmailPasswordlessDto {
  @IsString()
  registrationToken!: string;

  @IsString()
  @Length(1, 100)
  displayName!: string;

  @IsBoolean()
  acceptedLegal!: boolean;

  @IsBoolean()
  acceptedPersonalData!: boolean;

  @IsOptional()
  @IsBoolean()
  acceptedMarketing?: boolean;

  @IsOptional()
  @IsString()
  platform?: string;

  @IsOptional()
  @IsString()
  legalDocumentVersion?: string;
}
