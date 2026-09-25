import { Equals, IsBoolean, IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';
import { LEGAL_DOCUMENT_VERSION } from '../legal-document-version';

export class PasswordlessStartDto {
  @IsString()
  @Length(1, 40)
  phone!: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  referralCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  referralId?: string;
}

export class PasswordlessCheckDto {
  @IsString()
  @Length(80, 80)
  challenge!: string;
}

export class PasswordlessCompleteDto {
  @IsString()
  @Length(80, 80)
  registrationToken!: string;

  @IsString()
  @Length(1, 100)
  displayName!: string;

  @Equals(true)
  acceptedLegal!: boolean;

  @Equals(true)
  acceptedPersonalData!: boolean;

  @IsOptional()
  @IsBoolean()
  acceptedMarketing?: boolean;

  @IsOptional()
  @IsIn(['IOS', 'ANDROID', 'WEB'])
  platform?: string;

  // Existing signup records the server's current document version.
  @IsOptional()
  @IsString()
  @MaxLength(30)
  @Equals(LEGAL_DOCUMENT_VERSION)
  legalDocumentVersion?: string;
}
