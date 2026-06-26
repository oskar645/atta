import {
  IsBoolean,
  IsIn,
  IsInt,
  IsArray,
  IsObject,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

const listingStatuses = [
  'pending',
  'approved',
  'rejected',
  'sold',
  'deleted',
  'archived',
] as const;

export class CreateListingDto {
  @IsOptional()
  @IsString()
  owner_email?: string;

  @IsOptional()
  @IsString()
  owner_name?: string;

  @IsString()
  title!: string;

  @IsString()
  description!: string;

  @IsString()
  category!: string;

  @IsOptional()
  @IsString()
  subcategory?: string;

  @IsInt()
  @Min(0)
  price!: number;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsBoolean()
  phone_hidden?: boolean;

  @IsOptional()
  @IsIn(listingStatuses)
  status?: (typeof listingStatuses)[number];

  @IsOptional()
  @IsObject()
  delivery?: Record<string, boolean>;

  @IsOptional()
  @IsObject()
  location?: Record<string, unknown>;

  @IsOptional()
  @IsString()
  deal_type?: string;

  @IsOptional()
  @IsString()
  real_estate_type?: string;

  @IsOptional()
  @IsString()
  clothes_type?: string;

  @IsOptional()
  @IsObject()
  car?: Record<string, unknown>;

  @IsOptional()
  @IsArray()
  photo_urls?: string[];
}
