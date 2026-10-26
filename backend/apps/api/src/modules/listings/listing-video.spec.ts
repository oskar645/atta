import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BadRequestException } from '@nestjs/common';
import { parseListingVideoUrl, resolveListingVideo } from './listing-video';

test('parses supported VK Video links without accepting embed html', () => {
  assert.deepEqual(
    parseListingVideoUrl('https://vkvideo.ru/video-123_456'),
    {
      provider: 'vk',
      originalUrl: 'https://vkvideo.ru/video-123_456',
      videoId: '-123_456',
    },
  );
  assert.equal(
    parseListingVideoUrl('https://vk.com/video?z=video-7_99%2Fpl_cat_updates').videoId,
    '-7_99',
  );
});

test('resolves the production VK Clip URL through VK embed metadata', async () => {
  const url = 'https://vkvideo.ru/clip-235619660_456239017';
  assert.equal(parseListingVideoUrl(url).videoId, '-235619660_456239017');

  const originalFetch = global.fetch;
  global.fetch = async () =>
    new Response(
      '<script>{"image":[{"url":"https:\\/\\/iv.okcdn.ru\\/getVideoPreview?id=20837472078525&idx=0&type=39&tkn=test&fn=vid_w"}]}</script>',
      { status: 200, headers: { 'content-type': 'text/html' } },
    );
  try {
    const video = await resolveListingVideo(url);
    assert.equal(video.provider, 'vk');
    assert.equal(video.videoId, '-235619660_456239017');
    assert.equal(
      video.playbackUrl,
      'https://vk.com/video_ext.php?oid=-235619660&id=456239017',
    );
    assert.match(video.thumbnailUrl, /^https:\/\/iv\.okcdn\.ru\/getVideoPreview\?/);
  } finally {
    global.fetch = originalFetch;
  }
});

test('parses supported Rutube video and shorts links', () => {
  const id = '7716bd3e665725c3c008ae7ab4ff02e2';
  assert.equal(parseListingVideoUrl(`https://rutube.ru/video/${id}/`).videoId, id);
  assert.equal(parseListingVideoUrl(`https://rutube.ru/shorts/${id}/`).provider, 'rutube');
});

test('rejects unsupported domains, insecure URLs, and non-video pages', () => {
  for (const value of [
    'https://example.com/video-1_2',
    'http://vk.com/video-1_2',
    'https://rutube.ru/channel/123',
    '<iframe src="https://vk.com/video-1_2"></iframe>',
  ]) {
    assert.throws(() => parseListingVideoUrl(value), BadRequestException);
  }
});
