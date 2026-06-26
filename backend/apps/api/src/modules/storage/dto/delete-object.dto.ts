import { IsIn, IsString } from 'class-validator';

export class DeleteObjectDto {
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
  key!: string;
}
