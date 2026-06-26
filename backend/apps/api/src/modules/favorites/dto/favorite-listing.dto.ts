import { IsString, MinLength } from 'class-validator';

export class FavoriteListingDto {
  @IsString()
  @MinLength(1)
  listing_id!: string;
}
