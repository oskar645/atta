CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS "listings_title_trgm_idx"
  ON "listings" USING GIN ("title" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_title_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("title", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "listings_description_trgm_idx"
  ON "listings" USING GIN ("description" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_description_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("description", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "listings_category_trgm_idx"
  ON "listings" USING GIN ("category" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_category_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("category", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "listings_subcategory_trgm_idx"
  ON "listings" USING GIN ("subcategory" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_subcategory_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("subcategory", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "listings_city_trgm_idx"
  ON "listings" USING GIN ("city" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_city_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("city", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "listings_address_trgm_idx"
  ON "listings" USING GIN ("address" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_address_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("address", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);

CREATE INDEX IF NOT EXISTS "listings_owner_name_trgm_idx"
  ON "listings" USING GIN ("owner_name" gin_trgm_ops);
CREATE INDEX IF NOT EXISTS "listings_owner_name_compact_trgm_idx"
  ON "listings" USING GIN (regexp_replace(lower(coalesce("owner_name", '')), '[^[:alnum:]]+', '', 'g') gin_trgm_ops);
