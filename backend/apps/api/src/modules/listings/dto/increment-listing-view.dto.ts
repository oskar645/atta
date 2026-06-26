import { IsOptional, IsString } from 'class-validator';

export class IncrementListingViewDto {
  @IsOptional()
  @IsString()
  viewer_user_id?: string;

  @IsOptional()
  @IsString()
  viewer_device_id?: string;
}
