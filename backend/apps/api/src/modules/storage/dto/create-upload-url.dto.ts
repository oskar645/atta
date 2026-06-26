import { IsIn, IsOptional, IsString } from 'class-validator';

export class CreateUploadUrlDto {
  @IsIn([
    'avatars',
    'listing-photos',
    'chat-images',
    'feed-ads',
    'support-images',
    'reports',
    'misc',
    'videos',
  ])
  bucket!:
    | 'avatars'
    | 'listing-photos'
    | 'chat-images'
    | 'feed-ads'
    | 'support-images'
    | 'reports'
    | 'misc'
    | 'videos';

  @IsString()
  fileName!: string;

  @IsOptional()
  @IsString()
  contentType?: string;
}
