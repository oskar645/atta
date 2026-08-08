-- Data fix for a confirmed published listing without ListingPhoto rows.
-- Do not run on production without explicit owner/operator confirmation.

begin;

update listings
set
  status = 'PENDING',
  rejection_reason = 'Добавьте минимум одну фотографию',
  moderation_note = 'Снято с публикации: у объявления нет фотографий.',
  published_at = null,
  moderated_at = now(),
  archived_at = null,
  deleted_at = null
where id = '1b327ba7-f15d-4eeb-aaeb-630df13c8c27'
  and not exists (
    select 1
    from listing_photos
    where listing_photos.listing_id = listings.id
  );

commit;
