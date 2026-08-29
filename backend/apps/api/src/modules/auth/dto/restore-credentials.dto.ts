import { IsObject, IsOptional, IsString, MinLength } from 'class-validator';

export class VerifyRestoreCredentialRegistrationDto {
  @IsObject()
  response!: Record<string, unknown>;
}

export class VerifyRestoreCredentialAuthenticationDto {
  @IsObject()
  response!: Record<string, unknown>;
}

export class RevokeRestoreCredentialDto {
  @IsOptional()
  @IsString()
  @MinLength(8)
  credentialId?: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  credential_id?: string;
}
