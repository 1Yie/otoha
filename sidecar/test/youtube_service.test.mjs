import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  mapBrowseFeedSections,
  mapAccountChannel,
  mapAccountProfile,
  mapAccountRecap,
  mapCommentThread,
  mapFeedSections,
  mapRawArtistDetail,
  mapRawPodcastShowDetail,
  mapSearchItems,
  mapPlaylist,
  mapTrack,
  serializeError,
  YouTubeService,
} from '../src/youtube_service.mjs';

function rawChartItem(videoId, rank, iconType) {
  return {
    musicResponsiveListItemRenderer: {
      playlistItemData: { videoId },
      customIndexColumn: {
        musicCustomIndexColumnRenderer: {
          text: { runs: [{ text: rank }] },
          icon: { iconType },
        },
      },
    },
  };
}

function rawExploreChartItem(videoId, title, rank, iconType) {
  return {
    musicResponsiveListItemRenderer: {
      ...rawChartItem(videoId, rank, iconType)
        .musicResponsiveListItemRenderer,
      flexColumns: [
        {
          musicResponsiveListItemFlexColumnRenderer: {
            text: {
              runs: [
                {
                  text: title,
                  navigationEndpoint: {
                    watchEndpoint: {
                      videoId,
                      watchEndpointMusicSupportedConfigs: {
                        watchEndpointMusicConfig: {
                          musicVideoType: 'MUSIC_VIDEO_TYPE_ATV',
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
        {
          musicResponsiveListItemFlexColumnRenderer: {
            text: {
              runs: [
                {
                  text: 'Chart artist',
                  navigationEndpoint: {
                    browseEndpoint: { browseId: 'UCchart-artist' },
                  },
                },
              ],
            },
          },
        },
      ],
      navigationEndpoint: { watchEndpoint: { videoId } },
    },
  };
}

function rawChartArtistItem(browseId, title, rank, iconType) {
  return {
    musicResponsiveListItemRenderer: {
      flexColumns: [
        {
          musicResponsiveListItemFlexColumnRenderer: {
            text: {
              runs: [
                {
                  text: title,
                  navigationEndpoint: {
                    browseEndpoint: { browseId },
                  },
                },
              ],
            },
          },
        },
      ],
      navigationEndpoint: {
        browseEndpoint: {
          browseId,
          browseEndpointContextSupportedConfigs: {
            browseEndpointContextMusicConfig: {
              pageType: 'MUSIC_PAGE_TYPE_ARTIST',
            },
          },
        },
      },
      thumbnail: {
        musicThumbnailRenderer: {
          thumbnail: {
            thumbnails: [
              {
                url: `https://example.test/${browseId}.jpg`,
                width: 60,
                height: 60,
              },
            ],
          },
        },
      },
      customIndexColumn: {
        musicCustomIndexColumnRenderer: {
          text: { runs: [{ text: rank }] },
          icon: { iconType },
        },
      },
    },
  };
}

function parsedChartArtistItem(id, title) {
  return {
    item_type: 'artist',
    id,
    title,
    endpoint: {
      payload: {
        browseId: id,
      },
    },
  };
}

function rawLibraryAlbumItem({
  id,
  title,
  artist,
  params = null,
  responsive = false,
}) {
  const titleValue = {
    runs: [
      {
        text: title,
        navigationEndpoint: {
          browseEndpoint: {
            browseId: id,
            ...(params ? { params } : {}),
            browseEndpointContextSupportedConfigs: {
              browseEndpointContextMusicConfig: {
                pageType: 'MUSIC_PAGE_TYPE_ALBUM',
              },
            },
          },
        },
      },
    ],
  };
  const subtitleValue = {
    runs: [
      { text: 'Album' },
      { text: ' • ' },
      {
        text: artist,
        navigationEndpoint: {
          browseEndpoint: {
            browseId: `UC-${artist.toLowerCase().replaceAll(' ', '-')}`,
            browseEndpointContextSupportedConfigs: {
              browseEndpointContextMusicConfig: {
                pageType: 'MUSIC_PAGE_TYPE_ARTIST',
              },
            },
          },
        },
      },
      { text: ' • ' },
      { text: '2025' },
    ],
  };
  const artwork = {
    musicThumbnailRenderer: {
      thumbnail: {
        thumbnails: [
          {
            url: `https://lh3.googleusercontent.com/${id}=w60-h60-l90-rj`,
            width: 60,
            height: 60,
          },
        ],
      },
    },
  };
  if (responsive) {
    return {
      musicResponsiveListItemRenderer: {
        flexColumns: [
          {
            musicResponsiveListItemFlexColumnRenderer: {
              text: titleValue,
            },
          },
          {
            musicResponsiveListItemFlexColumnRenderer: {
              text: subtitleValue,
            },
          },
        ],
        thumbnail: artwork,
      },
    };
  }
  return {
    musicTwoRowItemRenderer: {
      title: titleValue,
      subtitle: subtitleValue,
      thumbnailRenderer: artwork,
    },
  };
}

function rawLibraryAlbumsResponse({
  items,
  continuation = null,
  continuationPage = false,
}) {
  const grid = {
    items,
    ...(continuation
      ? {
          continuations: [
            { nextContinuationData: { continuation } },
          ],
        }
      : {}),
  };
  return {
    success: true,
    status_code: 200,
    data: continuationPage
      ? { continuationContents: { gridContinuation: grid } }
      : {
          contents: {
            singleColumnBrowseResultsRenderer: {
              tabs: [
                {
                  tabRenderer: {
                    selected: true,
                    content: {
                      sectionListRenderer: {
                        contents: [{ gridRenderer: grid }],
                      },
                    },
                  },
                },
              ],
            },
          },
        },
  };
}

function rawExploreResponse({
  items = [],
  sections,
  continuation = null,
  includeCharts = true,
} = {}) {
  const contentSections =
    sections ?? (items.length ? [{ title: 'Popular songs', items }] : []);
  return {
    success: true,
    status_code: 200,
    data: {
      contents: {
        singleColumnBrowseResultsRenderer: {
          tabs: [
            {
              tabRenderer: {
                selected: true,
                content: {
                  sectionListRenderer: {
                    contents: [
                      ...(includeCharts
                        ? [
                            {
                              gridRenderer: {
                                items: [
                                  {
                                    musicNavigationButtonRenderer: {
                                      buttonText: {
                                        runs: [{ text: 'Charts' }],
                                      },
                                      clickCommand: {
                                        browseEndpoint: {
                                          browseId: 'FEmusic_charts',
                                          params: 'charts-params',
                                        },
                                      },
                                    },
                                  },
                                ],
                              },
                            },
                          ]
                        : []),
                      ...contentSections.map((section) => ({
                        musicCarouselShelfRenderer: {
                          header: {
                            musicCarouselShelfBasicHeaderRenderer: {
                              title: { runs: [{ text: section.title }] },
                            },
                          },
                          contents: section.items,
                        },
                      })),
                    ],
                    ...(continuation
                      ? {
                          continuations: [
                            {
                              nextContinuationData: { continuation },
                            },
                          ],
                        }
                      : {}),
                  },
                },
              },
            },
          ],
        },
      },
    },
  };
}

test('maps playlist and track parser shapes to the process contract', () => {
  assert.deepEqual(
    mapPlaylist({
      constructor: { type: 'GridPlaylist' },
      id: 'VLLM',
      title: { toString: () => 'Liked music' },
      author: { name: 'Listener' },
      video_count: { toString: () => '42 songs' },
      thumbnails: [
        { url: 'small', width: 120 },
        { url: 'large', width: 480 },
      ],
    }),
    {
      id: 'LM',
      title: 'Liked music',
      owner: 'Listener',
      itemCount: '42 songs',
      thumbnailUrl: 'large',
    },
  );

  assert.deepEqual(
    mapTrack({
      item_type: 'song',
      id: 'video-id',
      title: 'Track title',
      artists: [{ name: 'Artist' }],
      album: { name: 'Album' },
      duration: { seconds: 183 },
      thumbnail: {
        contents: [
          {
            url: 'https://lh3.googleusercontent.com/cover=w544-h544-l90-rj',
            width: 544,
          },
        ],
      },
    }),
    {
      videoId: 'video-id',
      itemType: 'song',
      title: 'Track title',
      artists: ['Artist'],
      album: 'Album',
      durationSeconds: 183,
      thumbnailUrl:
        'https://lh3.googleusercontent.com/cover=w1200-h1200-l90-rj',
    },
  );

  assert.deepEqual(
    mapTrack({
      item_type: 'non_music_track',
      id: 'episode-id',
      title: 'Podcast episode',
      second_title: 'Today · 42 min',
    }),
    {
      videoId: 'episode-id',
      itemType: 'non_music_track',
      title: 'Podcast episode',
      artists: [],
      album: null,
      durationSeconds: 2520,
      thumbnailUrl: null,
    },
  );
});

test('maps active account metadata without inventing a channel ID', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapAccountProfile([
      {
        account_name: text('Other channel'),
        account_photo: [],
        is_selected: false,
      },
      {
        account_name: text('Otoha listener'),
        channel_handle: text('@otoha-listener'),
        endpoint: {
          payload: {
            supportedTokens: [
              { accountStateToken: { hasChannel: true } },
            ],
          },
        },
        account_photo: [
          { url: 'small-avatar', width: 48 },
          { url: 'large-avatar', width: 256 },
        ],
        is_selected: true,
      },
    ]),
    {
      displayName: 'Otoha listener',
      avatarUrl: 'large-avatar',
      handle: '@otoha-listener',
      channelId: null,
    },
  );
});

test('maps a channel header and constructs controlled YouTube URLs', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapAccountChannel(
      {
        header: {
          author: {
            name: 'Otoha listener',
            thumbnails: [{ url: 'channel-avatar', width: 256 }],
          },
          banner: [],
          mobile_banner: [
            { url: 'small-banner', width: 640 },
          ],
          tv_banner: [
            { url: 'large-banner', width: 2120 },
          ],
          subscribers: text('12 subscribers'),
          channel_handle: text('@otoha-listener'),
          channel_id: 'UCotoha-listener',
        },
      },
      null,
    ),
    {
      displayName: 'Otoha listener',
      avatarUrl: 'channel-avatar',
      handle: '@otoha-listener',
      channelId: 'UCotoha-listener',
      subscriberText: '12 subscribers',
      bannerUrl: 'large-banner',
      channelUrl: 'https://www.youtube.com/@otoha-listener',
      studioUrl: 'https://studio.youtube.com/channel/UCotoha-listener',
    },
  );
});

test('maps modern page-header channel identity and artwork', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapAccountChannel({
      header: {
        page_title: 'Page title fallback',
        content: {
          title: { text: text('Modern listener') },
          image: {
            avatar: {
              image: [
                { url: 'small-modern-avatar', width: 48 },
                { url: 'large-modern-avatar', width: 256 },
              ],
            },
          },
          metadata: {
            metadata_rows: [
              {
                metadata_parts: [
                  { text: text('@modern-listener') },
                  { text: text('42 subscribers') },
                ],
              },
            ],
          },
          banner: {
            image: [{ url: 'modern-banner', width: 2048 }],
          },
        },
      },
      metadata: { external_id: 'UCmodern-listener' },
    }),
    {
      displayName: 'Modern listener',
      avatarUrl: 'large-modern-avatar',
      handle: '@modern-listener',
      channelId: 'UCmodern-listener',
      subscriberText: '42 subscribers',
      bannerUrl: 'modern-banner',
      channelUrl: 'https://www.youtube.com/@modern-listener',
      studioUrl: 'https://studio.youtube.com/channel/UCmodern-listener',
    },
  );
  assert.deepEqual(
    mapAccountChannel(
      {
        header: {
          title: text('Interactive listener'),
          metadata: text('7 subscribers'),
          box_art: [{ url: 'interactive-avatar', width: 512 }],
          banner: [{ url: 'interactive-banner', width: 2560 }],
        },
      },
      {
        handle: '@interactive-listener',
        channelId: 'UCinteractive-listener',
      },
    ),
    {
      displayName: 'Interactive listener',
      avatarUrl: 'interactive-avatar',
      handle: '@interactive-listener',
      channelId: 'UCinteractive-listener',
      subscriberText: '7 subscribers',
      bannerUrl: 'interactive-banner',
      channelUrl: 'https://www.youtube.com/@interactive-listener',
      studioUrl: 'https://studio.youtube.com/channel/UCinteractive-listener',
    },
  );
});

test('maps only official recap highlights and feed sections', () => {
  assert.deepEqual(
    mapAccountRecap({
      header: {
        panels: [
          {
            title: 'Your recent listening',
            strapline: 'Private',
            description: '1,234 minutes',
            background_image: {
              image: [{ url: 'recap-background', width: 1920 }],
            },
          },
        ],
      },
      sections: [
        {
          title: 'Top songs',
          contents: [
            {
              item_type: 'song',
              id: 'song-id',
              title: 'Most played song',
            },
          ],
        },
      ],
    }),
    {
      available: true,
      highlights: [
        {
          title: 'Your recent listening',
          strapline: 'Private',
          description: '1,234 minutes',
          backgroundUrl: 'recap-background',
          thumbnailUrl: null,
        },
      ],
      sections: [
        {
          title: 'Top songs',
          items: [
            {
              id: 'song-id',
              itemType: 'song',
              title: 'Most played song',
              subtitle: null,
              videoId: 'song-id',
              artists: [],
              album: null,
              durationSeconds: 0,
              thumbnailUrl: null,
            },
          ],
        },
      ],
    },
  );
  assert.deepEqual(mapAccountRecap(null), {
    available: false,
    highlights: [],
    sections: [],
  });
});

test('loads channel content and recap independently for the selected account', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.profile = {
    displayName: 'Fallback name',
    avatarUrl: 'fallback-avatar',
    handle: '@otoha-listener',
    channelId: 'UCotoha-listener',
  };
  service.innertube = {
    getChannel: async (channelId) => {
      calls.push(['channel', channelId]);
      return {
        header: {
          author: { name: 'Channel name', thumbnails: [] },
          channel_id: 'UCotoha-listener',
        },
      };
    },
    actions: {
      execute: async (endpoint, request) => {
        calls.push(['content', endpoint, request]);
        return {
          contents: {
            item: () => ({
              tabs: [
                {
                  selected: true,
                  content: {
                    contents: [
                      {
                        header: { title: 'Songs on repeat' },
                        num_items_per_column: 4,
                        contents: [
                          {
                            item_type: 'song',
                            id: 'repeat-song',
                            title: 'Repeat song',
                          },
                        ],
                      },
                      {
                        header: { title: 'Artists on repeat' },
                        contents: [
                          {
                            item_type: 'artist',
                            id: 'UCartist',
                            title: 'Repeat artist',
                          },
                        ],
                      },
                    ],
                  },
                },
              ],
            }),
          },
        };
      },
    },
    music: {
      getRecap: async () => {
        calls.push(['recap']);
        throw new Error('Recap is not available yet.');
      },
    },
  };

  const result = await service.getAccountChannel();

  assert.equal(result.profile.displayName, 'Channel name');
  assert.equal(result.profile.avatarUrl, 'fallback-avatar');
  assert.deepEqual(
    result.content.sections.map((section) => ({
      title: section.title,
      itemsPerColumn: section.itemsPerColumn,
      itemType: section.items[0].itemType,
    })),
    [
      {
        title: 'Songs on repeat',
        itemsPerColumn: 4,
        itemType: 'song',
      },
      {
        title: 'Artists on repeat',
        itemsPerColumn: undefined,
        itemType: 'artist',
      },
    ],
  );
  assert.deepEqual(result.recap, {
    available: false,
    highlights: [],
    sections: [],
  });
  assert.deepEqual(calls, [
    ['channel', 'UCotoha-listener'],
    [
      'content',
      'browse',
      {
        browseId: 'UCotoha-listener',
        client: 'YTMUSIC',
        parse: true,
      },
    ],
    ['recap'],
  ]);
  assert.equal(JSON.stringify(result).includes('SID='), false);
});

test('loads private channel-home content for the selected account', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.profile = {
    displayName: 'Fallback name',
    avatarUrl: 'fallback-avatar',
    handle: '@otoha-listener',
    channelId: 'UCotoha-listener',
  };
  service.innertube = {
    getChannel: async (channelId) => {
      calls.push(['channel', channelId]);
      return {
        header: {
          author: { name: 'Channel name', thumbnails: [] },
          banner: [{ url: 'youtube-small-banner', width: 640 }],
          tv_banner: [{ url: 'youtube-large-banner', width: 2120 }],
          channel_id: 'UCotoha-listener',
        },
      };
    },
    actions: {
      execute: async (endpoint, request) => {
        calls.push(['content', endpoint, request]);
        return {
          header: {
            banner: [{ url: 'ytmusic-banner', width: 4096 }],
          },
          contents: {
            item: () => ({
              tabs: [
                {
                  selected: true,
                  content: {
                    contents: [
                      {
                        header: {
                          title: 'Personalized playlists',
                          strapline: 'Private',
                        },
                        num_items_per_column: 4,
                        contents: [
                          {
                            item_type: 'song',
                            id: 'repeat-song',
                            title: 'Repeat song',
                          },
                        ],
                      },
                      {
                        header: {
                          title: 'Most listened artists',
                          strapline: 'Recent · Private',
                        },
                        contents: [
                          {
                            item_type: 'artist',
                            id: 'UCartist',
                            title: 'Repeat artist',
                          },
                        ],
                      },
                    ],
                  },
                },
              ],
            }),
          },
        };
      },
    },
  };

  const result = await service.getAccountChannel();

  assert.equal(result.profile.displayName, 'Channel name');
  assert.equal(result.profile.avatarUrl, 'fallback-avatar');
  assert.equal(result.profile.bannerUrl, 'youtube-large-banner');
  assert.deepEqual(
    result.content.sections.map((section) => ({
      title: section.title,
      subtitle: section.subtitle,
      itemsPerColumn: section.itemsPerColumn,
      itemType: section.items[0].itemType,
    })),
    [
      {
        title: 'Personalized playlists',
        subtitle: 'Private',
        itemsPerColumn: 4,
        itemType: 'song',
      },
      {
        title: 'Most listened artists',
        subtitle: 'Recent · Private',
        itemsPerColumn: undefined,
        itemType: 'artist',
      },
    ],
  );
  assert.deepEqual(calls, [
    ['channel', 'UCotoha-listener'],
    [
      'content',
      'browse',
      {
        browseId: 'UCotoha-listener',
        client: 'YTMUSIC',
        parse: true,
      },
    ],
  ]);
  assert.equal(JSON.stringify(result).includes('SID='), false);
});

test('resolves a handle before loading private channel-home content', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.profile = {
    displayName: 'Fallback name',
    avatarUrl: 'fallback-avatar',
    handle: '@otoha-listener',
    channelId: null,
  };
  service.innertube = {
    resolveURL: async (url) => {
      calls.push(['resolve', url]);
      return { payload: { browseId: 'UCresolved-listener' } };
    },
    getChannel: async (target) => {
      calls.push(['channel', target]);
      return {
        header: {
          author: { name: 'Channel name', thumbnails: [] },
          banner: [{ url: 'resolved-channel-banner', width: 2120 }],
        },
        metadata: { external_id: 'UCresolved-listener' },
      };
    },
    actions: {
      execute: async (endpoint, request) => {
        calls.push(['content', endpoint, request]);
        return {
          contents: {
            item: () => ({
              tabs: [
                {
                  selected: true,
                  content: {
                    contents: [
                      {
                        header: {
                          title: 'Personalized playlists',
                          strapline: 'Private',
                        },
                        contents: [
                          {
                            item_type: 'playlist',
                            id: 'personal-radio',
                            title: 'Listener radio',
                          },
                        ],
                      },
                    ],
                  },
                },
              ],
            }),
          },
        };
      },
    },
  };

  const result = await service.getAccountChannel();

  assert.equal(result.profile.channelId, 'UCresolved-listener');
  assert.equal(result.profile.bannerUrl, 'resolved-channel-banner');
  assert.equal(result.content.sections[0].title, 'Personalized playlists');
  assert.equal(result.content.sections[0].subtitle, 'Private');
  assert.equal(result.content.sections[0].items[0].title, 'Listener radio');
  assert.equal(service.status().profile.channelId, 'UCresolved-listener');
  assert.deepEqual(calls, [
    ['resolve', 'https://www.youtube.com/@otoha-listener'],
    ['channel', 'UCresolved-listener'],
    [
      'content',
      'browse',
      {
        browseId: 'UCresolved-listener',
        client: 'YTMUSIC',
        parse: true,
      },
    ],
  ]);
});

test('does not browse a handle when URL resolution is not a channel', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.profile = {
    displayName: 'Fallback name',
    avatarUrl: 'fallback-avatar',
    handle: '@otoha-listener',
    channelId: null,
  };
  service.innertube = {
    resolveURL: async (url) => {
      calls.push(['resolve', url]);
      return { payload: { browseId: 'FEwhat_to_watch' } };
    },
    getChannel: async (target) => calls.push(['channel', target]),
    actions: {
      execute: async (endpoint, request) => {
        calls.push(['content', endpoint, request]);
        return null;
      },
    },
  };

  const result = await service.getAccountChannel();

  assert.equal(result.profile.displayName, 'Fallback name');
  assert.equal(result.profile.channelId, null);
  assert.equal(result.profile.bannerUrl, null);
  assert.deepEqual(result.content.sections, []);
  assert.deepEqual(calls, [
    ['resolve', 'https://www.youtube.com/@otoha-listener'],
  ]);
});

test('keeps official recap when the public channel request fails', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.profile = {
    displayName: 'Fallback name',
    avatarUrl: 'fallback-avatar',
    handle: '@otoha-listener',
    channelId: 'UCotoha-listener',
  };
  service.innertube = {
    getChannel: async () => {
      throw new Error('Channel header unavailable.');
    },
    actions: {
      execute: async () => {
        throw new Error('Channel content unavailable.');
      },
    },
    music: {
      getRecap: async () => ({
        header: {
          panels: [{ title: 'Official recap', description: '42 minutes' }],
        },
        sections: [],
      }),
    },
  };

  const result = await service.getAccountChannel();

  assert.equal(result.profile.displayName, 'Fallback name');
  assert.equal(result.profile.bannerUrl, null);
  assert.deepEqual(result.content, { sections: [] });
  assert.equal(result.recap.available, true);
  assert.equal(result.recap.highlights[0].title, 'Official recap');
});

test('reports a retryable channel failure when no account data is usable', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.profile = null;
  service.innertube = {
    account: {
      getInfo: async () => {
        throw new Error('Profile unavailable.');
      },
    },
    music: {
      getRecap: async () => {
        throw new Error('Recap unavailable.');
      },
    },
  };

  await assert.rejects(
    () => service.getAccountChannel(),
    (error) => error.code === 'CHANNEL_LOAD_FAILED',
  );
});

test('accepts a Cookie when the music library works without a profile', async () => {
  const calls = [];
  const credentials = [];
  const service = new YouTubeService({
    createInnertube: async (cookie) => {
      calls.push({ method: 'create', cookie });
      return {
        account: {
          getInfo: async (all) => {
            calls.push({ method: 'profile', all });
            throw new Error('Profile endpoint unavailable.');
          },
        },
        music: {
          getLibrary: async () => {
            calls.push({ method: 'library' });
            return {};
          },
        },
      };
    },
    emit: (event, data) => credentials.push({ event, data }),
  });

  assert.deepEqual(
    await service.signInWithCookie('Cookie: SID=test-cookie; SAPISID=test'),
    { authenticated: true, mode: 'cookie', profile: null },
  );
  assert.deepEqual(calls, [
    { method: 'create', cookie: 'SID=test-cookie; SAPISID=test' },
    { method: 'profile', all: true },
    { method: 'library' },
  ]);
  assert.equal(
    credentials[0].data.credential.value,
    'SID=test-cookie; SAPISID=test',
  );
});

test('rejects a Cookie when the authenticated music library returns 401', async () => {
  const credentials = [];
  const service = new YouTubeService({
    createInnertube: async () => ({
      account: {
        getInfo: async () => ({ contents: { contents: [] } }),
      },
      music: {
        getLibrary: async () => {
          throw Object.assign(
            new Error('Request failed with status code 401'),
            {
              info: JSON.stringify({ error: { code: 401 } }),
            },
          );
        },
      },
    }),
    emit: (event, data) => credentials.push({ event, data }),
  });

  await assert.rejects(
    service.signInWithCookie('SID=expired-cookie'),
    (error) =>
      error.code === 'INVALID_COOKIE' &&
      error.details.diagnosticStage === 'auth.library' &&
      error.details.statusCode === 401,
  );

  assert.deepEqual(service.status(), {
    authenticated: false,
    mode: null,
    profile: null,
  });
  assert.deepEqual(credentials, []);
});

test('reports session network failures separately from rejected Cookies', async () => {
  const service = new YouTubeService({
    createInnertube: async () => {
      throw new TypeError('fetch failed', {
        cause: Object.assign(new Error('connection reset'), {
          code: 'ECONNRESET',
        }),
      });
    },
  });

  await assert.rejects(
    service.signInWithCookie('SID=test-cookie'),
    (error) =>
      error.code === 'AUTHENTICATION_UNAVAILABLE' &&
      error.details.diagnosticStage === 'auth.session' &&
      error.details.upstreamCode === 'ECONNRESET',
  );
});

test('creates and recreates sessions with the requested interface language', async () => {
  const calls = [];
  const service = new YouTubeService({
    createInnertube: async (cookie, locale) => {
      calls.push({ cookie, locale });
      return {};
    },
  });

  await service.restore(null, 'zh');
  await service.setLocale('en');

  assert.deepEqual(calls, [
    { cookie: null, locale: 'zh-CN' },
    { cookie: null, locale: 'en' },
  ]);
});

test('maps mixed music feed sections to stable item data', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapFeedSections([
      {
        header: { title: text('Listen again') },
        contents: [
          {
            constructor: { type: 'MusicTwoRowItem' },
            item_type: 'playlist',
            id: 'VLPL1',
            title: text('Daily mix'),
            subtitle: text('Made for listener'),
            thumbnail: [{ url: 'mix-cover', width: 320 }],
          },
          {
            constructor: { type: 'MusicResponsiveListItem' },
            item_type: 'song',
            id: 'video-1',
            title: 'Track title',
            artists: [{ name: 'Artist' }],
            duration: { seconds: 180 },
          },
        ],
      },
    ]),
    [
      {
        title: 'Listen again',
        items: [
          {
            id: 'PL1',
            itemType: 'playlist',
            title: 'Daily mix',
            subtitle: 'Made for listener',
            videoId: null,
            artists: [],
            album: null,
            durationSeconds: 0,
            thumbnailUrl: 'mix-cover',
          },
          {
            id: 'video-1',
            itemType: 'song',
            title: 'Track title',
            subtitle: 'Artist',
            videoId: 'video-1',
            artists: ['Artist'],
            album: null,
            durationSeconds: 180,
            thumbnailUrl: null,
          },
        ],
      },
    ],
  );
});

test('prefers complete feed clock text over a conflicting seconds field', () => {
  const sections = mapFeedSections([
    {
      title: 'Songs',
      contents: [
        {
          constructor: { type: 'MusicResponsiveListItem' },
          item_type: 'song',
          id: 'video-1',
          title: 'Track title',
          duration: { text: '3:45', seconds: 45 },
        },
      ],
    },
  ]);

  assert.equal(sections[0].items[0].durationSeconds, 225);
});

test('preserves native multi-row carousel layout metadata', () => {
  const text = (value) => ({ toString: () => value });
  const sections = mapFeedSections([
    {
      header: { title: text('Long listens') },
      num_items_per_column: 4,
      contents: [
        {
          constructor: { type: 'MusicResponsiveListItem' },
          item_type: 'video',
          id: 'long-video',
          title: 'Eight hour mix',
          duration: { seconds: 28800 },
        },
      ],
    },
  ]);

  assert.equal(sections[0].itemsPerColumn, 4);
  assert.equal(sections[0].items[0].id, 'long-video');
});

test('classifies feed navigation and collection items before tracks', () => {
  const text = (value) => ({ toString: () => value });
  const sections = mapFeedSections([
    {
      header: { title: text('Browse') },
      contents: [
        {
          constructor: { type: 'MusicNavigationButton' },
          button_text: 'Chill',
          endpoint: {
            payload: {
              browseId: 'FEmusic_moods_and_genres_category',
              params: 'chill-params',
            },
          },
        },
        {
          item_type: 'MUSIC_ARTIST',
          title: text('Artist'),
          endpoint: { payload: { browseId: 'UCartist' } },
        },
        {
          content_type: 'MUSIC_ALBUM',
          title: text('Album'),
          endpoint: { payload: { browseId: 'MPREalbum' } },
        },
        {
          item_type: 'song',
          id: 'track-id',
          title: text('Track'),
          endpoint: { payload: { videoId: 'track-id' } },
        },
      ],
    },
  ]);

  expectEqual(sections[0].items.map((item) => item.itemType), [
    'category',
    'artist',
    'album',
    'song',
  ]);
  assert.equal(sections[0].items[0].browseParams, 'chill-params');
  assert.equal(sections[0].items[1].videoId, null);
  assert.equal(sections[0].items[2].videoId, null);
  assert.equal(sections[0].items[3].videoId, 'track-id');
});

test('maps podcast episodes as playable feed items', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapFeedSections([
      {
        header: { title: text('Popular episodes') },
        contents: [
          {
            constructor: { type: 'MusicMultiRowListItem' },
            id: 'MPSP-podcast-browse-id',
            title: text('Podcast episode'),
            subtitle: text('Podcast creator'),
            on_tap: { payload: { videoId: 'podcast-id' } },
          },
        ],
      },
      {
        header: { title: text('Songs') },
        contents: [
          {
            item_type: 'song',
            id: 'song-id',
            title: text('Music track'),
            endpoint: { payload: { videoId: 'song-id' } },
          },
        ],
      },
    ]),
    [
      {
        title: 'Popular episodes',
        items: [
          {
            id: 'MPSP-podcast-browse-id',
            itemType: 'episode',
            title: 'Podcast episode',
            subtitle: 'Podcast creator',
            videoId: 'podcast-id',
            artists: [],
            album: null,
            durationSeconds: 0,
            thumbnailUrl: null,
          },
        ],
      },
      {
        title: 'Songs',
        items: [
          {
            id: 'song-id',
            itemType: 'song',
            title: 'Music track',
            subtitle: null,
            videoId: 'song-id',
            artists: [],
            album: null,
            durationSeconds: 0,
            thumbnailUrl: null,
          },
        ],
      },
    ],
  );
});

test('maps podcast show browse cards as navigation instead of video', () => {
  const text = (value) => ({ toString: () => value });
  const [section] = mapFeedSections([
    {
      header: { title: text('Podcasts') },
      contents: [
        {
          constructor: { type: 'MusicTwoRowItem' },
          item_type: 'video',
          id: 'MPSP-podcast-show',
          title: text('Podcast show'),
          endpoint: {
            payload: { browseId: 'MPSP-podcast-show' },
          },
        },
      ],
    },
  ]);

  assert.equal(section.items[0].itemType, 'podcast');
  assert.equal(section.items[0].videoId, null);
  assert.equal(section.items[0].id, 'MPSP-podcast-show');
});

test('maps searchable music items and removes duplicate entries', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapSearchItems([
      {
        contents: [
          {
            item_type: 'song',
            id: 'track-id',
            title: text('Track'),
            endpoint: { payload: { videoId: 'track-id' } },
            artists: [{ name: 'Artist' }],
          },
          {
            item_type: 'channel',
            id: 'UCcreator',
            title: text('Creator'),
            endpoint: { payload: { browseId: 'UCcreator' } },
          },
          {
            item_type: 'non_music_track',
            id: 'podcast-id',
            title: text('Podcast result'),
            endpoint: { payload: { videoId: 'podcast-id' } },
          },
        ],
      },
      {
        contents: [
          {
            item_type: 'song',
            id: 'track-id',
            title: text('Track'),
            endpoint: { payload: { videoId: 'track-id' } },
          },
        ],
      },
    ]),
    [
      {
        id: 'track-id',
        itemType: 'song',
        title: 'Track',
        subtitle: 'Artist',
        videoId: 'track-id',
        artists: ['Artist'],
        album: null,
        durationSeconds: 0,
        thumbnailUrl: null,
      },
      {
        id: 'UCcreator',
        itemType: 'channel',
        title: 'Creator',
        subtitle: null,
        videoId: null,
        artists: [],
        album: null,
        durationSeconds: 0,
        thumbnailUrl: null,
      },
      {
        id: 'podcast-id',
        itemType: 'non_music_track',
        title: 'Podcast result',
        subtitle: null,
        videoId: 'podcast-id',
        artists: [],
        album: null,
        durationSeconds: 0,
        thumbnailUrl: null,
      },
    ],
  );
});

test('forwards typed music search filters and rejects unsupported values', async () => {
  const calls = [];
  const text = (value) => ({ toString: () => value });
  const service = new YouTubeService();
  service.innertube = {
    music: {
      search: async (query, options) => {
        calls.push({ query, options });
        return {
          contents: [
            {
              contents: [
                {
                  item_type: 'song',
                  id: `result-${options.type}`,
                  title: text(`Result ${options.type}`),
                  endpoint: {
                    payload: { videoId: `result-${options.type}` },
                  },
                },
              ],
            },
          ],
        };
      },
    },
  };

  for (const filter of ['all', 'song', 'album', 'artist', 'playlist', 'video']) {
    const result = await service.searchMusic(`query ${filter}`, filter);
    assert.equal(result.items[0].id, `result-${filter}`);
  }

  assert.deepEqual(
    calls,
    ['all', 'song', 'album', 'artist', 'playlist', 'video'].map((filter) => ({
      query: `query ${filter}`,
      options: { type: filter },
    })),
  );
  await assert.rejects(
    service.searchMusic('query', 'podcast'),
    (error) => error.code === 'INVALID_SEARCH_FILTER',
  );
});

test('maps a browse result tab into feed sections', () => {
  const page = {
    contents: {
      item: () => ({
        tabs: [
          {
            content: {
              contents: [
                {
                  header: { title: 'Chill picks' },
                  contents: [
                    {
                      item_type: 'playlist',
                      id: 'VLplaylist',
                      title: 'Playlist',
                    },
                  ],
                },
              ],
            },
          },
        ],
      }),
    },
  };

  assert.deepEqual(mapBrowseFeedSections(page), [
    {
      title: 'Chill picks',
      items: [
        {
          id: 'playlist',
          itemType: 'playlist',
          title: 'Playlist',
          subtitle: null,
          videoId: null,
          artists: [],
          album: null,
          durationSeconds: 0,
          thumbnailUrl: null,
        },
      ],
    },
  ]);
});

test('maps singleton browse fields without assuming parser arrays', () => {
  const page = {
    contents: {
      tabs: {
        selected: true,
        content: {
          contents: {
            header: { title: 'Artist picks' },
            contents: {
              item_type: 'song',
              id: 'video-id',
              title: 'Track',
              artists: { name: 'Artist' },
            },
          },
        },
      },
    },
  };

  assert.deepEqual(mapBrowseFeedSections(page), [
    {
      title: 'Artist picks',
      items: [
        {
          id: 'video-id',
          itemType: 'song',
          title: 'Track',
          subtitle: 'Artist',
          videoId: 'video-id',
          artists: ['Artist'],
          album: null,
          durationSeconds: 0,
          thumbnailUrl: null,
        },
      ],
    },
  ]);
});

test('preserves parsed and raw chart rank semantics', () => {
  const page = {
    contents: {
      tabs: {
        selected: true,
        content: {
          contents: {
            header: { title: 'Popular songs' },
            contents: [
              {
                item_type: 'song',
                id: 'ranked-up',
                title: 'Rising track',
                index: { toString: () => '1' },
              },
              {
                item_type: 'song',
                id: 'ranked-down',
                title: 'Falling track',
              },
              {
                item_type: 'song',
                id: 'ranked-neutral',
                title: 'Steady track',
              },
            ],
          },
        },
      },
    },
  };
  const rawPage = {
    contents: [
      rawChartItem('ranked-up', '1', 'ARROW_DROP_UP'),
      rawChartItem('ranked-down', '2', 'TRENDING_DOWN'),
      rawChartItem('ranked-neutral', '3', 'ARROW_CHART_NEUTRAL'),
    ],
  };

  const [section] = mapBrowseFeedSections(page, rawPage);

  assert.equal(section.title, 'Popular songs');
  assert.deepEqual(
    section.items.map(({ id, rank, trend }) => ({ id, rank, trend })),
    [
      { id: 'ranked-up', rank: 1, trend: 'up' },
      { id: 'ranked-down', rank: 2, trend: 'down' },
      { id: 'ranked-neutral', rank: 3, trend: 'neutral' },
    ],
  );
});

test('attaches raw chart rank through every renderer-local video identity', () => {
  const page = {
    contents: {
      tabs: {
        selected: true,
        content: {
          contents: {
            header: { title: 'Popular songs' },
            contents: [
              {
                item_type: 'song',
                id: 'treat-u-right-official',
                title: 'treat u right',
                index: { toString: () => '3' },
              },
              {
                item_type: 'artist',
                id: 'UCchart-artist',
                title: 'Chart artist',
                index: { toString: () => '9' },
              },
            ],
          },
        },
      },
    },
  };
  const rawItem = rawChartItem(
    'renderer-surface-alias',
    '6',
    'ARROW_DROP_UP',
  );
  rawItem.musicResponsiveListItemRenderer.flexColumns = [
    {
      musicResponsiveListItemFlexColumnRenderer: {
        text: {
          runs: [
            {
              text: 'treat u right',
              navigationEndpoint: {
                watchEndpoint: { videoId: 'treat-u-right-official' },
              },
            },
          ],
        },
      },
    },
    {
      musicResponsiveListItemFlexColumnRenderer: {
        text: {
          runs: [
            {
              text: 'Chart artist',
              navigationEndpoint: {
                browseEndpoint: { browseId: 'UCchart-artist' },
              },
            },
          ],
        },
      },
    },
  ];

  const [section] = mapBrowseFeedSections(page, { contents: [rawItem] });

  assert.deepEqual(
    section.items.map(({ id, rank, trend }) => ({ id, rank, trend })),
    [
      { id: 'treat-u-right-official', rank: 6, trend: 'up' },
      { id: 'UCchart-artist', rank: 9, trend: undefined },
    ],
  );
});

test('attaches chart ranks and trends to primary artist browse identities', () => {
  const artists = [
    { id: 'UCfavorite-up', title: 'Favorite artist up' },
    { id: 'UCfavorite-down', title: 'Favorite artist down' },
    { id: 'UCfavorite-neutral', title: 'Favorite artist neutral' },
  ];
  const page = {
    contents: {
      tabs: {
        selected: true,
        content: {
          contents: [
            {
              header: { title: 'Popular songs' },
              contents: [
                {
                  item_type: 'song',
                  id: 'popular-song',
                  title: 'Popular song',
                },
              ],
            },
            {
              header: { title: 'Favorite artists' },
              contents: artists.map(({ id, title }) =>
                parsedChartArtistItem(id, title)),
            },
          ],
        },
      },
    },
  };
  const rawPage = rawExploreResponse({
    includeCharts: false,
    sections: [
      {
        title: 'Popular songs',
        items: [
          rawExploreChartItem(
            'popular-song',
            'Popular song',
            '8',
            'ARROW_DROP_UP',
          ),
        ],
      },
      {
        title: 'Favorite artists',
        items: [
          rawChartArtistItem(
            'UCfavorite-up',
            'Favorite artist up',
            '1',
            'ARROW_DROP_UP',
          ),
          rawChartArtistItem(
            'UCfavorite-down',
            'Favorite artist down',
            '2',
            'TRENDING_DOWN',
          ),
          rawChartArtistItem(
            'UCfavorite-neutral',
            'Favorite artist neutral',
            '3',
            'ARROW_CHART_NEUTRAL',
          ),
        ],
      },
    ],
  }).data;

  const [songsSection, artistsSection] = mapBrowseFeedSections(page, rawPage);

  assert.deepEqual(
    songsSection.items.map(({ id, rank, trend }) => ({ id, rank, trend })),
    [{ id: 'popular-song', rank: 8, trend: 'up' }],
  );
  assert.equal(artistsSection.title, 'Favorite artists');
  assert.deepEqual(
    artistsSection.items.map(({ id, rank, trend }) => ({ id, rank, trend })),
    [
      { id: 'UCfavorite-up', rank: 1, trend: 'up' },
      { id: 'UCfavorite-down', rank: 2, trend: 'down' },
      { id: 'UCfavorite-neutral', rank: 3, trend: 'neutral' },
    ],
  );
});

test('preserves raw artist ranks through the Charts browse service', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    actions: {
      execute: async (endpoint, args) => {
        calls.push({ endpoint, args });
        return rawExploreResponse({
          includeCharts: false,
          sections: [
            {
              title: 'Favorite artists',
              items: [
                rawChartArtistItem(
                  'UCfavorite-up',
                  'Favorite artist up',
                  '1',
                  'ARROW_DROP_UP',
                ),
                rawChartArtistItem(
                  'UCfavorite-neutral',
                  'Favorite artist neutral',
                  '2',
                  'ARROW_CHART_NEUTRAL',
                ),
              ],
            },
          ],
        });
      },
    },
  };

  const result = await service.getFeedBrowse('category', 'FEmusic_charts');

  assert.deepEqual(calls, [
    {
      endpoint: 'browse',
      args: {
        browseId: 'FEmusic_charts',
        client: 'YTMUSIC',
      },
    },
  ]);
  assert.deepEqual(
    result.sections[0].items.map(({ id, rank, trend }) => ({
      id,
      rank,
      trend,
    })),
    [
      { id: 'UCfavorite-up', rank: 1, trend: 'up' },
      { id: 'UCfavorite-neutral', rank: 2, trend: 'neutral' },
    ],
  );
});

test('keeps duplicate track ranks scoped to each browse section', () => {
  const sharedItem = {
    item_type: 'song',
    id: 'shared-browse-track',
    title: 'Shared browse track',
  };
  const page = {
    contents: {
      tabs: {
        selected: true,
        content: {
          contents: [
            {
              header: { title: 'Popular songs' },
              contents: [sharedItem],
            },
            {
              header: { title: 'Trending' },
              contents: [sharedItem],
            },
          ],
        },
      },
    },
  };
  const rawPage = rawExploreResponse({
    sections: [
      {
        title: 'Popular songs',
        items: [
          rawExploreChartItem(
            'shared-browse-track',
            'Shared browse track',
            '6',
            'TRENDING_DOWN',
          ),
        ],
      },
      {
        title: 'Trending',
        items: [
          rawExploreChartItem(
            'shared-browse-track',
            'Shared browse track',
            '3',
            'ARROW_DROP_UP',
          ),
        ],
      },
    ],
  }).data;

  const sections = mapBrowseFeedSections(page, rawPage);

  assert.deepEqual(
    sections.map((section) => ({
      title: section.title,
      rank: section.items[0].rank,
      trend: section.items[0].trend,
    })),
    [
      { title: 'Popular songs', rank: 6, trend: 'down' },
      { title: 'Trending', rank: 3, trend: 'up' },
    ],
  );
});

test('maps refreshed artist header metadata from the raw Music response', () => {
  assert.deepEqual(
    mapRawArtistDetail({
      header: {
        musicImmersiveHeaderRenderer: {
          title: { runs: [{ text: 'Fresh artist name' }] },
          subtitle: { simpleText: 'Monthly audience: 5.6M' },
          thumbnail: {
            musicThumbnailRenderer: {
              thumbnail: {
                thumbnails: [
                  { url: 'small-cover', width: 64 },
                  { url: 'artist-cover', width: 544 },
                ],
              },
            },
          },
          subscriptionButton: {
            subscribeButtonRenderer: {
              channelId: 'UCcanonical-artist',
              subscribed: true,
              subscriberCountText: { simpleText: '2.4M subscribers' },
            },
          },
        },
      },
    }),
    {
      title: 'Fresh artist name',
      subtitle: 'Monthly audience: 5.6M',
      audience: 'Monthly audience: 5.6M',
      thumbnailUrl: 'artist-cover',
      channelId: 'UCcanonical-artist',
      subscriberCount: '2.4M subscribers',
      subscribed: true,
    },
  );
});

test('loads artist header metadata from the same raw browse response', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    actions: {
      execute: async (endpoint, args) => {
        calls.push([endpoint, args]);
        return {
          success: true,
          status_code: 200,
          data: {
            header: {
              musicImmersiveHeaderRenderer: {
                title: { runs: [{ text: 'Fresh artist name' }] },
                thumbnail: {
                  musicThumbnailRenderer: {
                    thumbnail: {
                      thumbnails: [{ url: 'artist-cover', width: 544 }],
                    },
                  },
                },
                subscriptionButton: {
                  subscribeButtonRenderer: {
                    buttonText: { runs: [{ text: 'Subscribe' }] },
                    channelId: 'UCcanonical-artist',
                    subscribed: false,
                    enabled: true,
                    type: 'FREE',
                    showPreferences: false,
                    subscriberCountText: { simpleText: '2.4M subscribers' },
                  },
                },
              },
            },
          },
        };
      },
    },
  };

  const result = await service.getFeedBrowse('artist', 'UCrequested-artist');

  assert.deepEqual(calls, [
    [
      'browse',
      {
        browseId: 'UCrequested-artist',
        client: 'YTMUSIC',
      },
    ],
  ]);
  assert.deepEqual(result, {
    artist: {
      title: 'Fresh artist name',
      subtitle: null,
      audience: null,
      thumbnailUrl: 'artist-cover',
      channelId: 'UCcanonical-artist',
      subscriberCount: '2.4M subscribers',
      subscribed: false,
    },
    sections: [],
  });
});

test('classifies collection and browse parsing failures by stage', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    music: {
      getAlbum: async () => ({}),
    },
    actions: {
      execute: async () => ({
        contents: {
          item: () => {
            throw new TypeError('parser mismatch');
          },
        },
      }),
    },
  };

  assert.deepEqual(
    await service.getFeedCollection('album', 'album-id'),
    { tracks: [] },
  );
  await assert.rejects(
    () => service.getFeedBrowse('category', 'FEmusic_category'),
    (error) =>
      error.code === 'BROWSE_PARSE_FAILED' &&
      error.details.diagnosticStage === 'browse.parse' &&
      error.details.errorType === 'TypeError',
  );
});

test('loads library playlist tracks through the Cookie-authenticated music session', async () => {
  const track = (id) => ({
    item_type: 'song',
    id,
    title: id,
    artists: [],
    duration: { seconds: 60 },
  });
  const continuation = {
    items: [track('second')],
    has_continuation: false,
  };
  const innertube = {
    account: {
      getInfo: async () => ({
        contents: {
          contents: [
            {
              account_name: { toString: () => 'Test listener' },
              account_photo: [],
            },
          ],
        },
      }),
    },
    music: {
      getPlaylist: async () => ({
        header: { title: 'Playlist' },
        items: [track('first')],
        has_continuation: true,
        getContinuation: async () => continuation,
      }),
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });

  await service.signInWithCookie('SID=test-cookie');
  const result = await service.getPlaylist('VLplaylist');

  assert.equal(result.playlist.id, 'playlist');
  assert.deepEqual(result.tracks.map((item) => item.videoId), ['first']);
  assert.equal(result.hasMore, true);
  assert.deepEqual(await service.getMorePlaylist('playlist'), {
    tracks: [
      {
        videoId: 'second',
        itemType: 'song',
        title: 'second',
        artists: [],
        album: null,
        durationSeconds: 60,
        thumbnailUrl: null,
      },
    ],
    hasMore: false,
  });
});

test('loads playlists, albums, saved collections, and followed artists for the media library', async () => {
  const session = new EventTarget();
  session.logged_in = true;
  session.on = session.addEventListener.bind(session);
  const playlists = {
    contents: [
      {
        contents: [
          {
            item_type: 'playlist',
            id: 'VLPL-road-trip',
            title: { toString: () => 'Road trip' },
          },
        ],
      },
    ],
    has_continuation: false,
  };
  const artists = {
    contents: [
      {
        contents: [
          {
            item_type: 'artist',
            id: 'UCartist',
            title: { toString: () => 'Artist one' },
            subtitle: { toString: () => 'Artist' },
            artists: [{ name: 'Artist one' }],
          },
        ],
      },
    ],
    has_continuation: false,
  };
  const podcasts = {
    contents: [
      {
        contents: [
          {
            item_type: 'playlist',
            id: 'VLSE',
            title: { toString: () => 'Episodes for later' },
          },
          {
            item_type: 'playlist',
            id: 'VLRDPN',
            title: { toString: () => 'New episodes' },
          },
          {
            item_type: 'podcast_show',
            id: 'MPSPshow',
            title: { toString: () => 'Saved podcast' },
            subtitle: { toString: () => 'Podcast author' },
          },
        ],
      },
    ],
    has_continuation: false,
  };
  const albums = {
    contents: [
      {
        contents: [
          {
            item_type: 'album',
            id: 'MPREalbum',
            title: { toString: () => 'Saved album' },
            subtitle: { toString: () => 'Album artist' },
          },
        ],
      },
    ],
    has_continuation: false,
  };
  const library = {
    filters: ['Playlists', 'Artists', 'Podcasts', 'Albums'],
    applyFilter: async (filter) => ({
      Playlists: playlists,
      Artists: artists,
      Podcasts: podcasts,
      Albums: albums,
    })[filter],
  };
  const innertube = {
    session,
    music: {
      getLibrary: async () => library,
    },
    getLibrary: async () => ({
      liked_videos: { title: { toString: () => 'Liked videos' } },
    }),
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(result.playlists.map((item) => item.id), ['PL-road-trip']);
  assert.equal(result.episodePlaylists, undefined);
  assert.deepEqual(
    result.podcasts.map((item) => [item.id, item.itemType, item.title]),
    [['MPSPshow', 'podcast', 'Saved podcast']],
  );
  assert.deepEqual(result.followedArtists.map((item) => item.id), ['UCartist']);
  assert.deepEqual(
    result.albums.map((item) => [item.id, item.itemType, item.title]),
    [['MPREalbum', 'album', 'Saved album']],
  );
  assert.deepEqual(result.savedCollections, [
    {
      id: 'liked_videos',
      specialKind: 'liked_videos',
      title: 'Liked videos',
    },
  ]);
});

test('loads albums from the canonical authenticated browse endpoint', async () => {
  const appliedFilters = [];
  const browseCalls = [];
  const events = [];
  let constructorCalls = 0;
  const playlists = { contents: [], has_continuation: false };
  const actions = {
    execute: async (endpoint, args) => {
      browseCalls.push({ endpoint, args });
      if (args.browseId === 'FEmusic_liked_albums') {
        return rawLibraryAlbumsResponse({
          items: [
            rawLibraryAlbumItem({
              id: 'MPREalbum-root',
              title: 'Root album',
              artist: 'Root artist',
              params: 'root-album-params',
            }),
          ],
          continuation: 'albums-next-token',
        });
      }
      assert.equal(args.continuation, 'albums-next-token');
      return rawLibraryAlbumsResponse({
        continuationPage: true,
        items: [
          rawLibraryAlbumItem({
            id: 'MPREalbum-next',
            title: 'Continued album',
            artist: 'Continued artist',
            responsive: true,
          }),
        ],
      });
    },
  };
  class FilteredLibrary {
    constructor() {
      constructorCalls += 1;
      throw new Error('The youtubei.js Library parser rejected this page.');
    }
  }
  const library = {
    filters: ['Playlists', 'Albums'],
    page: {
      contents_memo: {
        getType: () => [
          {
            chips: [
              {
                text: 'Albums',
                endpoint: {
                payload: {
                  commands: [
                    { updateToggleButtonStateCommand: { toggled: true } },
                    {
                      browseSectionListReloadEndpoint: {
                        continuation: {
                          reloadContinuationData: {
                            continuation: 'albums-reload-token',
                          },
                        },
                      },
                    },
                  ],
                  },
                },
              },
            ],
          },
        ],
      },
    },
    applyFilter: async (filter) => {
      appliedFilters.push(filter);
      if (filter === 'Albums') {
        throw new Error('The Albums applyFilter path must not run.');
      }
      return playlists;
    },
    constructor: FilteredLibrary,
  };
  const innertube = {
    actions,
    music: { getLibrary: async () => library },
  };
  const service = new YouTubeService({
    createInnertube: async () => innertube,
    emit: (event, data) => events.push({ event, data }),
  });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(
    result.albums.map((item) => ({
      id: item.id,
      title: item.title,
      artists: item.artists,
      browseParams: item.browseParams ?? null,
    })),
    [
      {
        id: 'MPREalbum-root',
        title: 'Root album',
        artists: ['Root artist'],
        browseParams: 'root-album-params',
      },
      {
        id: 'MPREalbum-next',
        title: 'Continued album',
        artists: ['Continued artist'],
        browseParams: null,
      },
    ],
  );
  assert.deepEqual(browseCalls, [
    {
      endpoint: 'browse',
      args: {
        browseId: 'FEmusic_liked_albums',
        client: 'YTMUSIC',
      },
    },
    {
      endpoint: 'browse',
      args: {
        continuation: 'albums-next-token',
        client: 'YTMUSIC',
      },
    },
  ]);
  assert.equal(constructorCalls, 0);
  assert.deepEqual(appliedFilters, ['Playlists']);
  assert.deepEqual(events, []);
});

test('stops Albums pagination when a continuation token repeats', async () => {
  const browseCalls = [];
  const actions = {
    execute: async (endpoint, args) => {
      browseCalls.push({ endpoint, args });
      return rawLibraryAlbumsResponse({
        continuationPage: args.continuation != null,
        items: [
          rawLibraryAlbumItem({
            id: args.continuation ? 'MPREalbum-next' : 'MPREalbum-root',
            title: args.continuation ? 'Continued album' : 'Root album',
            artist: 'Album artist',
          }),
        ],
        continuation: 'repeated-albums-token',
      });
    },
  };
  const library = {
    filters: ['Playlists', 'Albums'],
    applyFilter: async () => ({ contents: [], has_continuation: false }),
  };
  const innertube = {
    actions,
    music: { getLibrary: async () => library },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(
    result.albums.map((item) => item.id),
    ['MPREalbum-root', 'MPREalbum-next'],
  );
  assert.deepEqual(browseCalls, [
    {
      endpoint: 'browse',
      args: {
        browseId: 'FEmusic_liked_albums',
        client: 'YTMUSIC',
      },
    },
    {
      endpoint: 'browse',
      args: {
        continuation: 'repeated-albums-token',
        client: 'YTMUSIC',
      },
    },
  ]);
});

test('parses the chip reload continuation when Albums browse is unavailable', async () => {
  const appliedFilters = [];
  const browseCalls = [];
  const events = [];
  const playlists = { contents: [], has_continuation: false };
  const actions = {
    execute: async (endpoint, args) => {
      browseCalls.push({ endpoint, args });
      if (args.browseId === 'FEmusic_liked_albums') {
        throw new Error('Dedicated Albums browse is unavailable.');
      }
      return rawLibraryAlbumsResponse({
        continuationPage: true,
        items: [
          rawLibraryAlbumItem({
            id: 'MPREalbum-reload',
            title: 'Reloaded album',
            artist: 'Album artist',
          }),
        ],
      });
    },
  };
  const library = {
    filters: ['Playlists', 'Albums'],
    page: {
      contents_memo: {
        getType: () => [
          {
            chips: [
              {
                text: 'Albums',
                endpoint: {
                  payload: {
                    commands: [
                      {
                        browseSectionListReloadEndpoint: {
                          continuation: {
                            reloadContinuationData: {
                              continuation: 'albums-reload-token',
                            },
                          },
                        },
                      },
                    ],
                  },
                },
              },
            ],
          },
        ],
      },
    },
    applyFilter: async (filter) => {
      appliedFilters.push(filter);
      if (filter === 'Albums') {
        throw new Error('The Albums applyFilter path must not run.');
      }
      return playlists;
    },
  };
  const innertube = {
    actions,
    music: { getLibrary: async () => library },
  };
  const service = new YouTubeService({
    createInnertube: async () => innertube,
    emit: (event, data) => events.push({ event, data }),
  });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(result.albums.map((item) => item.id), [
    'MPREalbum-reload',
  ]);
  assert.deepEqual(browseCalls, [
    {
      endpoint: 'browse',
      args: { browseId: 'FEmusic_liked_albums', client: 'YTMUSIC' },
    },
    {
      endpoint: 'browse',
      args: {
        continuation: 'albums-reload-token',
        client: 'YTMUSIC',
      },
    },
  ]);
  assert.deepEqual(appliedFilters, ['Playlists']);
  assert.deepEqual(events, []);
});

test('keeps playlists when an optional library filter fails', async () => {
  const events = [];
  const playlists = {
    contents: [
      {
        contents: [
          {
            item_type: 'playlist',
            id: 'VLPL-working',
            title: { toString: () => 'Working playlist' },
          },
        ],
      },
    ],
    has_continuation: false,
  };
  const library = {
    filters: ['Playlists', 'Albums'],
    applyFilter: async (filter) => {
      if (filter === 'Albums') {
        throw new Error('Expected an api_url, but none was found.');
      }
      return playlists;
    },
  };
  const innertube = {
    music: { getLibrary: async () => library },
  };
  const service = new YouTubeService({
    createInnertube: async () => innertube,
    emit: (event, data) => events.push({ event, data }),
  });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(result.playlists.map((item) => item.id), ['PL-working']);
  assert.deepEqual(result.albums, []);
  assert.equal(events.length, 1);
  assert.equal(events[0].event, 'library.section_unavailable');
  assert.equal(events[0].data.method, 'library.media');
  assert.equal(events[0].data.code, 'LIBRARY_SECTION_UNAVAILABLE');
  assert.equal(events[0].data.errorType, 'Error');
  assert.equal(events[0].data.diagnosticStage, 'library.filter.albums');
  assert.match(
    events[0].data.sourceLocation,
    /^sidecar\/src\/youtube_service\.mjs:\d+:\d+$/,
  );
  assert.equal(JSON.stringify(events).includes('api_url'), false);
});

test('reports optional library continuation failures as collection failures', async () => {
  const events = [];
  const emptyPage = { contents: [], has_continuation: false };
  const podcasts = {
    contents: [],
    has_continuation: true,
    getContinuation: async () => {
      throw new Error('Podcast continuation failed.');
    },
  };
  const library = {
    filters: ['Playlists', 'Podcasts'],
    applyFilter: async (filter) =>
      filter === 'Podcasts' ? podcasts : emptyPage,
  };
  const innertube = {
    music: { getLibrary: async () => library },
  };
  const service = new YouTubeService({
    createInnertube: async () => innertube,
    emit: (event, data) => events.push({ event, data }),
  });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(result.podcasts, []);
  assert.equal(events.length, 1);
  assert.equal(events[0].event, 'library.section_unavailable');
  assert.equal(events[0].data.method, 'library.media');
  assert.equal(events[0].data.code, 'LIBRARY_SECTION_UNAVAILABLE');
  assert.equal(events[0].data.errorType, 'Error');
  assert.equal(events[0].data.diagnosticStage, 'library.collect.podcasts');
  assert.match(
    events[0].data.sourceLocation,
    /^sidecar\/src\/youtube_service\.mjs:\d+:\d+$/,
  );
});

test('keeps playlist library failures fatal with a section stage', async () => {
  const library = {
    filters: ['Playlists'],
    applyFilter: async () => {
      throw new Error('Playlist filter failed.');
    },
  };
  const innertube = {
    music: { getLibrary: async () => library },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';

  await assert.rejects(
    service.getLibraryMedia(),
    (error) =>
      error.code === 'LIBRARY_LOAD_FAILED' &&
      error.details.diagnosticStage === 'library.filter.playlists' &&
      error.details.errorType === 'Error',
  );
});

test('does not invent podcast library entries when the filter is unavailable', async () => {
  const library = {
    filters: ['Playlists'],
    contents: [
      {
        contents: [
          {
            item_type: 'playlist',
            id: 'VLSE',
            title: { toString: () => 'Root-page lookalike' },
          },
        ],
      },
    ],
    has_continuation: false,
    applyFilter: async () => ({
      contents: [],
      has_continuation: false,
    }),
  };
  const innertube = {
    music: {
      getLibrary: async () => library,
    },
    getLibrary: async () => ({}),
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.deepEqual(result.playlists, []);
  assert.equal(result.episodePlaylists, undefined);
  assert.deepEqual(result.podcasts, []);
  assert.deepEqual(result.albums, []);
  assert.deepEqual(result.savedCollections, []);
});

test('ignores automatic lists and deduplicates shows across continuations', async () => {
  const nextPodcasts = {
    contents: [
      {
        contents: [
          {
            item_type: 'playlist',
            id: 'VLSE',
            title: { toString: () => 'Episodes for later' },
          },
          {
            item_type: 'podcast_show',
            id: 'MPSPshow',
            title: { toString: () => 'Saved podcast' },
          },
        ],
      },
    ],
    has_continuation: false,
  };
  const podcasts = {
    contents: nextPodcasts.contents,
    has_continuation: true,
    getContinuation: async () => nextPodcasts,
  };
  const library = {
    filters: ['Podcasts'],
    applyFilter: async () => podcasts,
  };
  const innertube = {
    music: {
      getLibrary: async () => library,
    },
    getLibrary: async () => ({}),
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';

  const result = await service.getLibraryMedia();

  assert.equal(result.episodePlaylists, undefined);
  assert.deepEqual(result.podcasts.map((item) => item.id), ['MPSPshow']);
});

test('loads Home and Explore continuations through the music client', async () => {
  const session = new EventTarget();
  session.logged_in = true;
  session.on = session.addEventListener.bind(session);
  const section = {
    header: { title: { toString: () => 'Recommendations' } },
    contents: [
      {
        item_type: 'playlist',
        id: 'VLPL1',
        title: { toString: () => 'Mix' },
      },
    ],
  };
  const nextHomeFeed = { sections: [section], has_continuation: false };
  const exploreSection = {
    header: { title: { toString: () => 'More to explore' } },
    contents: [
      {
        item_type: 'playlist',
        id: 'VLPL2',
        title: { toString: () => 'Another mix' },
      },
    ],
  };
const initialHomeFeed = {
sections: [section],
filters: ['Podcasts', 'Sleep'],
has_continuation: true,
getContinuation: async () => nextHomeFeed,
applyFilter: async (filter) => ({
sections: [
{
header: { title: { toString: () => `${filter} picks` } },
contents: [
{
item_type: 'playlist',
id: 'VLPL-filtered',
title: { toString: () => `${filter} mix` },
},
],
},
],
has_continuation: false,
}),
};
  const exploreContinuation = {
    continuation_contents: {
      as: () => ({
        contents: { as: () => [exploreSection] },
        continuation: undefined,
      }),
    },
  };
  const innertube = {
    session,
    music: {
      getHomeFeed: async () => initialHomeFeed,
    },
    actions: {
      execute: async (endpoint, args) => {
        assert.equal(endpoint, '/browse');
        assert.equal(args.client, 'YTMUSIC');
        if (args.browseId === 'FEmusic_explore') {
          return rawExploreResponse({
            items: [
              rawExploreChartItem(
                'explore-track',
                'Explore track',
                '1',
                'ARROW_DROP_UP',
              ),
            ],
            continuation: 'explore-token',
          });
        }
        assert.equal(args.continuation, 'explore-token');
        assert.equal(args.parse, true);
        return exploreContinuation;
      },
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';
  service.authMode = 'cookie';

const home = await service.getHomeFeed();
assert.equal(home.sections[0].title, 'Recommendations');
assert.deepEqual(home.filters, ['Podcasts', 'Sleep']);
assert.equal(home.selectedFilter, null);
assert.equal(home.hasMore, true);
assert.equal((await service.getMoreHomeFeed()).hasMore, false);
assert.deepEqual(await service.getMoreHomeFeed(), { sections: [], hasMore: false });
const filteredHome = await service.applyHomeFilter('Sleep');
assert.equal(filteredHome.sections[0].title, 'Sleep picks');
assert.equal(filteredHome.sections[0].items[0].id, 'PL-filtered');
assert.equal(filteredHome.selectedFilter, 'Sleep');
const explore = await service.getExploreFeed();
  assert.equal(explore.sections[0].title, 'Explore');
  assert.deepEqual(explore.sections[0].items[0], {
    id: 'FEmusic_charts',
    itemType: 'category',
    title: 'Charts',
    subtitle: null,
    videoId: null,
    browseParams: 'charts-params',
    artists: [],
    album: null,
    durationSeconds: 0,
    thumbnailUrl: null,
  });
  assert.equal(explore.sections[1].items[0].id, 'explore-track');
  assert.equal(explore.sections[1].items[0].trend, 'up');
  assert.equal(explore.hasMore, true);
  const moreExplore = await service.getMoreExploreFeed();
  assert.equal(moreExplore.sections[0].title, 'More to explore');
  assert.equal(moreExplore.sections[0].items[0].id, 'PL2');
  assert.equal(moreExplore.hasMore, false);
  assert.deepEqual(await service.getMoreExploreFeed(), {
    sections: [],
    hasMore: false,
  });
});

test('falls back to the canonical localized Charts destination', async () => {
  const innertube = {
    actions: {
      execute: async () => rawExploreResponse({ includeCharts: false }),
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.locale = 'zh-CN';

  const result = await service.getExploreFeed();

  assert.equal(result.sections[0].items[0].id, 'FEmusic_charts');
  assert.equal(result.sections[0].items[0].title, '排行榜');
  assert.equal(result.hasMore, false);
});

test('preserves raw up, down, and neutral trends in Explore', async () => {
  const calls = [];
  const innertube = {
    actions: {
      execute: async (endpoint, args) => {
        calls.push({ endpoint, args });
        return rawExploreResponse({
          items: [
            rawExploreChartItem('chart-up', 'Rising track', '1', 'ARROW_DROP_UP'),
            rawExploreChartItem(
              'chart-down',
              'Falling track',
              '2',
              'TRENDING_DOWN',
            ),
            rawExploreChartItem(
              'chart-neutral',
              'Steady track',
              '3',
              'ARROW_CHART_NEUTRAL',
            ),
          ],
        });
      },
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;

  const result = await service.getExploreFeed();

  assert.deepEqual(calls, [
    {
      endpoint: '/browse',
      args: { client: 'YTMUSIC', browseId: 'FEmusic_explore' },
    },
  ]);
  assert.deepEqual(
    result.sections[1].items.map(({ id, rank, trend }) => ({
      id,
      rank,
      trend,
    })),
    [
      { id: 'chart-up', rank: 1, trend: 'up' },
      { id: 'chart-down', rank: 2, trend: 'down' },
      { id: 'chart-neutral', rank: 3, trend: 'neutral' },
    ],
  );
});

test('keeps duplicate track ranks scoped to each Explore section', async () => {
  const innertube = {
    actions: {
      execute: async () =>
        rawExploreResponse({
          sections: [
            {
              title: 'Popular songs',
              items: [
                rawExploreChartItem(
                  'shared-chart-track',
                  'Shared chart track',
                  '6',
                  'TRENDING_DOWN',
                ),
              ],
            },
            {
              title: 'Trending',
              items: [
                rawExploreChartItem(
                  'shared-chart-track',
                  'Shared chart track',
                  '3',
                  'ARROW_DROP_UP',
                ),
              ],
            },
          ],
        }),
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;

  const result = await service.getExploreFeed();

  assert.deepEqual(
    result.sections.slice(1).map((section) => ({
      title: section.title,
      rank: section.items[0].rank,
      trend: section.items[0].trend,
    })),
    [
      { title: 'Popular songs', rank: 6, trend: 'down' },
      { title: 'Trending', rank: 3, trend: 'up' },
    ],
  );
});

test('loads authenticated YouTube Music history as playable tracks', async () => {
  const historyItem = {
    constructor: { type: 'Video' },
    id: 'history-video',
    title: { toString: () => 'History track' },
    author: { name: 'History artist' },
    duration: { seconds: 213 },
    thumbnails: [{ url: 'https://example.test/history.jpg' }],
  };
  const olderHistoryItem = {
    ...historyItem,
    id: 'older-history-video',
    title: { toString: () => 'Older history track' },
  };
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    actions: {
      execute: async (endpoint, params) => {
        assert.equal(endpoint, '/browse');
        if (params.continuation) {
          assert.deepEqual(params, {
            client: 'YTMUSIC',
            continuation: 'history-token',
          });
          return {
            continuation_contents: {
              as: () => ({
                contents: [historyItem, olderHistoryItem],
                continuation: null,
              }),
            },
          };
        }
        assert.deepEqual(params, {
          browseId: 'FEmusic_history',
          client: 'YTMUSIC',
          parse: true,
        });
        return {
          contents_memo: {
            getType: () => [
              {
                contents: [historyItem, historyItem],
                continuation: 'history-token',
              },
            ],
          },
        };
      },
    },
  };

  const result = await service.getHistory();

  assert.deepEqual(result, {
    tracks: [
    {
      videoId: 'history-video',
      itemType: 'song',
      title: 'History track',
      artists: ['History artist'],
      album: null,
      durationSeconds: 213,
      thumbnailUrl: 'https://example.test/history.jpg',
    },
    ],
    hasMore: true,
  });
  assert.deepEqual(
    (await service.getMoreHistory()).tracks.map((item) => item.videoId),
    ['older-history-video'],
  );
  assert.deepEqual(await service.getMoreHistory(), { tracks: [], hasMore: false });
});

test('treats an empty Home continuation response as exhausted', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    music: {
      getHomeFeed: async () => ({
        sections: [],
        has_continuation: true,
        getContinuation: async () => {
          throw new Error('Continuation did not have any content.');
        },
      }),
    },
  };

  await service.getHomeFeed();
  assert.deepEqual(await service.getMoreHomeFeed(), {
    sections: [],
    hasMore: false,
  });
});

test('loads feed playlist and album tracks through the music session', async () => {
  const session = new EventTarget();
  session.logged_in = false;
  session.on = session.addEventListener.bind(session);
  const track = (id) => ({
    item_type: 'song',
    id,
    title: id,
    artists: [],
    duration: { seconds: 60 },
  });
  const innertube = {
    session,
    music: {
      getAlbum: async () => ({
        header: {
          buttons: [
            {
              endpoint: {
                payload: { playlistId: 'OLAK-album-target' },
              },
            },
          ],
        },
        contents: [track('album-track')],
      }),
      getPlaylist: async () => ({
        items: [track('playlist-track')],
        has_continuation: false,
      }),
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;
  service.authMode = 'cookie';

  assert.deepEqual(
    (await service.getFeedCollection('album', 'MPRalbum')).tracks.map(
      (item) => item.videoId,
    ),
    ['album-track'],
  );
  assert.equal(
    service.albumLibraryTargets.get('MPRalbum'),
    'OLAK-album-target',
  );
  assert.deepEqual(
    (await service.getFeedCollection('playlist', 'PL1')).tracks.map(
      (item) => item.videoId,
    ),
    ['playlist-track'],
  );
});

test('updates album library through the cached official audio playlist target', async () => {
  const calls = [];
  let now = 0;
  let albumRequests = 0;
  const album = {
    header: {
      buttons: [
        {
          endpoint: {
            payload: { playlistId: 'OLAK-official-album' },
          },
        },
      ],
    },
    contents: [],
  };
  const innertube = {
    music: {
      getAlbum: async (albumId) => {
        albumRequests += 1;
        assert.equal(albumId, 'MPREalbum');
        return album;
      },
    },
    actions: {
      execute: async (endpoint, payload) => {
        calls.push([endpoint, payload]);
        return { success: true, status_code: 200 };
      },
    },
  };
  const service = new YouTubeService({
    createInnertube: async () => innertube,
    now: () => now,
  });
  service.innertube = innertube;
  service.authMode = 'cookie';

  assert.deepEqual(await service.setAlbumInLibrary('MPREalbum', true), {
    albumId: 'MPREalbum',
    saved: true,
  });
  await assert.rejects(
    service.setAlbumInLibrary('MPREalbum', false),
    (error) => serializeError(error).code === 'ACCOUNT_WRITE_THROTTLED',
  );
  now += 2000;
  assert.deepEqual(await service.setAlbumInLibrary('MPREalbum', false), {
    albumId: 'MPREalbum',
    saved: false,
  });
  assert.equal(albumRequests, 1);
  assert.deepEqual(calls, [
    [
      'like/like',
      {
        target: { playlistId: 'OLAK-official-album' },
        client: 'YTMUSIC',
      },
    ],
    [
      'like/removelike',
      {
        target: { playlistId: 'OLAK-official-album' },
        client: 'YTMUSIC',
      },
    ],
  ]);
  assert.equal(service.albumLibraryTargets.size, 1);

  await service.setLocale('zh-CN');
  assert.equal(service.albumLibraryTargets.size, 0);
});

test('reports unavailable and failed album library mutations distinctly', async () => {
  const unavailable = new YouTubeService();
  unavailable.authMode = 'cookie';
  unavailable.innertube = {
    music: { getAlbum: async () => ({ header: {}, contents: [] }) },
  };
  await assert.rejects(
    unavailable.setAlbumInLibrary('MPREmissing', true),
    (error) => {
      assert.equal(
        serializeError(error).code,
        'ALBUM_LIBRARY_TARGET_UNAVAILABLE',
      );
      return true;
    },
  );

  const failed = new YouTubeService();
  failed.authMode = 'cookie';
  failed.innertube = {
    music: {
      getAlbum: async () => ({
        header: {
          buttons: [
            {
              endpoint: {
                payload: { playlistId: 'OLAK-failed-album' },
              },
            },
          ],
        },
      }),
    },
    actions: {
      execute: async () => ({ success: false, status_code: 503 }),
    },
  };
  await assert.rejects(failed.setAlbumInLibrary('MPREfailed', true), (error) => {
    const serialized = serializeError(error);
    assert.equal(serialized.code, 'ALBUM_LIBRARY_UPDATE_FAILED');
    assert.equal(serialized.details.diagnosticStage, 'album.library.update');
    assert.equal(serialized.details.statusCode, 503);
    return true;
  });

  await assert.rejects(failed.setAlbumInLibrary('', true), (error) => {
    assert.equal(serializeError(error).code, 'INVALID_ALBUM_ID');
    return true;
  });
  await assert.rejects(
    failed.setAlbumInLibrary('MPREfailed', 'saved'),
    (error) => {
      assert.equal(
        serializeError(error).code,
        'INVALID_ALBUM_LIBRARY_STATE',
      );
      return true;
    },
  );
});

test('resolves missing feed-song duration from basic video metadata', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async (videoId, options) => {
      calls.push({ videoId, options });
      return {
        basic_info: {
          id: videoId,
          title: 'Resolved song',
          author: 'Artist',
          duration: 247,
          thumbnail: [{ url: 'resolved-cover', width: 640 }],
        },
      };
    },
  };

  assert.deepEqual(await service.getFeedTrack('video-id'), {
    track: {
      videoId: 'video-id',
      title: 'Resolved song',
      artists: ['Artist'],
      durationSeconds: 247,
      thumbnailUrl: 'resolved-cover',
    },
  });
  assert.deepEqual(calls, [
    { videoId: 'video-id', options: { client: 'YTMUSIC' } },
  ]);
});

test('resolves an authenticated audio-only playback stream without credentials', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async (videoId, options) => {
      calls.push({ videoId, options });
      return {
        streaming_data: {
          adaptive_formats: [
            {
              has_audio: true,
              has_video: false,
              is_original: true,
              url: 'https://audio.example.test/stream?token=short-lived',
              mime_type: 'audio/webm; codecs="opus"',
              bitrate: 128000,
              approx_duration_ms: 213000,
            },
          ],
        },
      };
    },
  };

  const result = await service.getPlaybackStream('video-id');

  assert.deepEqual(result, {
    stream: {
      url: 'https://audio.example.test/stream?token=short-lived',
      mimeType: 'audio/webm; codecs="opus"',
      bitrate: 128000,
      durationSeconds: 213,
      mediaType: 'audio',
    },
  });
  assert.deepEqual(calls, [
    {
      videoId: 'video-id',
      options: {
        client: 'YTMUSIC',
      },
    },
  ]);
  assert.equal(JSON.stringify(result).includes('SID='), false);
});

test('selects deterministic capped audio bitrates for playback quality', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async () => ({
      basic_info: { duration: 200 },
      streaming_data: {
        adaptive_formats: [32_000, 48_000, 96_000, 128_000, 192_000].map(
          (bitrate, index) => ({
            has_audio: true,
            has_video: false,
            is_original: true,
            bitrate,
            itag: index + 1,
            mime_type: 'audio/webm; codecs="opus"',
            decipher: async () => `https://audio.example.test/${bitrate}`,
          }),
        ),
      },
    }),
  };

  const low = await service.getPlaybackStream('video-id', 'audio', 'low');
  const normal = await service.getPlaybackStream('video-id', 'audio', 'normal');
  const high = await service.getPlaybackStream('video-id', 'audio', 'high');

  assert.equal(low.stream.bitrate, 48_000);
  assert.equal(normal.stream.bitrate, 128_000);
  assert.equal(high.stream.bitrate, 192_000);
  assert.equal(low.stream.url, 'https://audio.example.test/48000');
});

test('rejects an unknown playback quality', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';

  await assert.rejects(
    () => service.getPlaybackStream('video-id', 'audio', 'lossless'),
    (error) => error.code === 'INVALID_AUDIO_QUALITY',
  );
});

test('falls back to another client for podcast audio playback', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async (videoId, options) => {
      calls.push({ videoId, options });
      if (options.client === 'YTMUSIC') {
        throw new Error('No matching formats found');
      }
      return {
        streaming_data: {
          adaptive_formats: [
            {
              has_audio: true,
              has_video: false,
              is_original: true,
              url: 'https://audio.example.test/podcast',
              mime_type: 'audio/mp4; codecs="mp4a.40.2"',
              bitrate: 96000,
              approx_duration_ms: 1800000,
            },
          ],
        },
      };
    },
  };

  const result = await service.getPlaybackStream('podcast-id');

  assert.equal(result.stream.mediaType, 'audio');
  assert.deepEqual(calls.map((call) => call.options.client), [
    'YTMUSIC',
    'YTMUSIC_ANDROID',
  ]);
});

test('resolves an adaptive DASH video stream for visible playback', async () => {
  const calls = [];
  const video2160 = {
    has_video: true,
    has_audio: false,
    height: 2160,
    bitrate: 12000000,
    mime_type: 'video/webm; codecs="vp9"',
    decipher: async () => 'https://video.example.test/2160',
  };
  const video1080Vp9 = {
    has_video: true,
    has_audio: false,
    height: 1080,
    bitrate: 5000000,
    mime_type: 'video/webm; codecs="vp9"',
    decipher: async () => 'https://video.example.test/1080-vp9',
  };
  const video1080Avc = {
    has_video: true,
    has_audio: false,
    height: 1080,
    bitrate: 4500000,
    mime_type: 'video/mp4; codecs="avc1.640028"',
    width: 1920,
    decipher: async () => 'https://video.example.test/1080-avc',
  };
  const alternateAudio = {
    has_video: false,
    has_audio: true,
    bitrate: 192000,
    mime_type: 'audio/webm; codecs="opus"',
    decipher: async () => 'https://audio.example.test/alternate',
  };
  const originalAudio = {
    has_video: false,
    has_audio: true,
    is_original: true,
    bitrate: 128000,
    mime_type: 'audio/mp4; codecs="mp4a.40.2"',
    decipher: async () => 'https://audio.example.test/original',
  };
  const originalLowAudio = {
    has_video: false,
    has_audio: true,
    is_original: true,
    bitrate: 48000,
    mime_type: 'audio/webm; codecs="opus"',
    decipher: async () => 'https://audio.example.test/original-low',
  };
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async (videoId, options) => {
      calls.push({ videoId, options });
      return {
        basic_info: { duration: 240, is_live: false },
        streaming_data: {
          adaptive_formats: [
            video2160,
            video1080Vp9,
            video1080Avc,
            alternateAudio,
            originalAudio,
            originalLowAudio,
          ],
        },
      };
    },
  };

  const result = await service.getPlaybackStream('video-id', 'video');

  assert.equal(result.stream.mediaType, 'video');
  assert.equal(result.stream.mimeType, 'video/mp4; codecs="avc1.640028"');
  assert.equal(result.stream.audioMimeType, 'audio/mp4; codecs="mp4a.40.2"');
  assert.equal(result.stream.url, 'https://video.example.test/1080-avc');
  assert.equal(result.stream.audioUrl, 'https://audio.example.test/original');
  assert.equal(result.stream.width, 1920);
  assert.equal(result.stream.height, 1080);
  const lowResult = await service.getPlaybackStream('video-id', 'video', 'low');
  assert.equal(lowResult.stream.audioUrl, 'https://audio.example.test/original-low');
  assert.deepEqual(calls, [
    {
      videoId: 'video-id',
      options: {
        client: 'YTMUSIC',
      },
    },
    {
      videoId: 'video-id',
      options: {
        client: 'YTMUSIC',
      },
    },
  ]);
});

test('does not expose the upstream failure when audio playback cannot resolve', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async () => {
      throw new Error('Fetch failed for https://audio.example.test/?token=secret');
    },
  };

  await assert.rejects(
    () => service.getPlaybackStream('video-id'),
    (error) =>
      error.code === 'PLAYBACK_RESOLUTION_FAILED' &&
      !error.message.includes('token=secret'),
  );
});

test('serializes only safe upstream failure diagnostics', () => {
  const error = Object.assign(
    new Error('Request rejected for https://music.example.test/?SID=secret'),
    { code: 'ECONNRESET', statusCode: 403 },
  );

  const serialized = serializeError(error);

  assert.deepEqual(serialized, {
    code: 'YOUTUBE_ERROR',
    message: 'The YouTube service could not complete this request.',
    details: {
      errorType: 'Error',
      statusCode: 403,
      upstreamCode: 'ECONNRESET',
    },
  });
  assert.equal(JSON.stringify(serialized).includes('secret'), false);
});

test('downloads audio without retaining its URL or replacing the signed-in session', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-download-'));
  const events = [];
  const downloadOptions = [];
  let replacementSessionCalls = 0;
  const downloadInnertube = {
    getBasicInfo: async (_videoId, options) => {
      downloadOptions.push(options);
      return {
        chooseFormat: (formatOptions) => {
          assert.deepEqual(formatOptions, options);
          return { mime_type: 'audio/webm; codecs="opus"' };
        },
        download: async (formatOptions) => {
          assert.deepEqual(formatOptions, options);
          return new ReadableStream({
            start(controller) {
              controller.enqueue(new Uint8Array([1, 2, 3, 4]));
              controller.close();
            },
          });
        },
      };
    },
  };
  const service = new YouTubeService({
    emit: (event, data) => events.push({ event, data }),
    fetchImpl: async () => {
      throw new Error('Global fetch must not download audio streams.');
    },
    createInnertube: async () => {
      replacementSessionCalls += 1;
      throw new Error('Downloads must not replace the signed-in session.');
    },
  });
  service.authMode = 'cookie';
  service.cookie = 'SID=session-cookie';
  service.profile = { name: 'Test account' };
  service.innertube = downloadInnertube;
  const primaryInnertube = service.innertube;
  const statusBeforeDownload = service.status();

  try {
    const result = await service.downloadAudio('video-id', directory);

    assert.equal(result.path, path.join(directory, 'video-id.webm'));
    assert.equal(result.mimeType, 'audio/webm; codecs="opus"');
    assert.deepEqual(await readFile(result.path), Buffer.from([1, 2, 3, 4]));
    assert.equal(events[0].event, 'download.progress');
    assert.equal(JSON.stringify(result).includes('token=short-lived'), false);
    assert.equal(service.innertube, primaryInnertube);
    assert.equal(replacementSessionCalls, 0);
    assert.deepEqual(downloadOptions, [
      {
        client: 'YTMUSIC',
        type: 'audio',
        quality: 'best',
        format: 'any',
      },
    ]);
    assert.deepEqual(service.status(), statusBeforeDownload);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('commits a self-contained offline media bundle atomically', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-bundle-'));
  const service = new YouTubeService({
    now: () => Date.parse('2026-07-15T00:00:00.000Z'),
    fetchImpl: async (url) => {
      assert.equal(String(url), 'https://example.test/cover');
      return new Response(new Uint8Array([9, 8, 7]), {
        status: 200,
        headers: { 'content-type': 'image/jpeg' },
      });
    },
  });
  service.authMode = 'cookie';
  service.downloadAudio = async (videoId, stagingPath) => {
    const audioPath = path.join(stagingPath, `${videoId}.webm`);
    await writeFile(audioPath, new Uint8Array([1, 2, 3, 4]));
    return {
      path: audioPath,
      mimeType: 'audio/webm; codecs="opus"',
      artworkUrl: null,
    };
  };
  service.getLyrics = async () => ({
    source: 'lrclib',
    lines: [
      { text: 'First line', startSeconds: 1.25 },
      { text: 'Second line', startSeconds: 62.5 },
    ],
  });

  try {
    const result = await service.downloadMediaBundle('video-id', directory, {
      title: 'Offline track',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 180,
      artworkUrl: 'https://example.test/cover',
    });

    assert.equal(result.bundlePath, path.join(directory, 'video-id'));
    assert.equal(result.path, path.join(result.bundlePath, 'audio.webm'));
    assert.equal(result.artworkPath, path.join(result.bundlePath, 'cover.jpg'));
    assert.equal(result.lyricsPath, path.join(result.bundlePath, 'lyrics.lrc'));
    assert.deepEqual(await readdir(result.bundlePath), [
      'audio.webm',
      'cover.jpg',
      'lyrics.lrc',
      'metadata.json',
    ]);
    assert.deepEqual(await readFile(result.path), Buffer.from([1, 2, 3, 4]));
    assert.deepEqual(await readFile(result.artworkPath), Buffer.from([9, 8, 7]));
    assert.equal(
      await readFile(result.lyricsPath, 'utf8'),
      '[00:01.25]First line\n[01:02.50]Second line\n',
    );
    const metadata = JSON.parse(
      await readFile(path.join(result.bundlePath, 'metadata.json'), 'utf8'),
    );
    assert.equal(metadata.videoId, 'video-id');
    assert.equal(metadata.artworkFile, 'cover.jpg');
    assert.equal(JSON.stringify(metadata).includes('example.test'), false);
    await assert.rejects(() => readdir(path.join(directory, 'video-id.part')));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('removes an incomplete media bundle when artwork fails', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-bundle-fail-'));
  const service = new YouTubeService({
    fetchImpl: async () => new Response(null, { status: 503 }),
  });
  service.authMode = 'cookie';
  service.downloadAudio = async (videoId, stagingPath) => {
    const audioPath = path.join(stagingPath, `${videoId}.m4a`);
    await writeFile(audioPath, new Uint8Array([1, 2, 3]));
    return {
      path: audioPath,
      mimeType: 'audio/mp4; codecs="mp4a.40.2"',
      artworkUrl: null,
    };
  };

  try {
    await assert.rejects(
      () => service.downloadMediaBundle('video-id', directory, {
        artworkUrl: 'https://example.test/missing-cover',
      }),
      (error) =>
        error.code === 'DOWNLOAD_ARTWORK_FAILED' &&
        error.details?.diagnosticStage === 'download.bundle.artwork',
    );
    await assert.rejects(() => readdir(path.join(directory, 'video-id.part')));
    await assert.rejects(() => readdir(path.join(directory, 'video-id')));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('falls back to another client when YTMUSIC has no audio format', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-download-client-'));
  const requestedClients = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.cookie = 'SID=session-cookie';
  service.innertube = {
    getBasicInfo: async (_videoId, options) => {
      requestedClients.push(options.client);
      if (options.client === 'YTMUSIC') {
        return {
          chooseFormat: () => {
            throw new Error('No matching formats found.');
          },
        };
      }
      return {
        chooseFormat: () => ({ mime_type: 'audio/mp4; codecs="mp4a.40.2"' }),
        download: async (downloadOptions) => {
          assert.equal(downloadOptions.client, 'YTMUSIC_ANDROID');
          return new ReadableStream({
            start(controller) {
              controller.enqueue(new Uint8Array([4, 3, 2, 1]));
              controller.close();
            },
          });
        },
      };
    },
  };

  try {
    const result = await service.downloadAudio('video-id', directory);

    assert.deepEqual(requestedClients, ['YTMUSIC', 'YTMUSIC_ANDROID']);
    assert.equal(result.path, path.join(directory, 'video-id.m4a'));
    assert.deepEqual(await readFile(result.path), Buffer.from([4, 3, 2, 1]));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('classifies audio format selection failures separately from metadata', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-download-format-'));
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async () => ({
      chooseFormat: () => {
        throw new Error('No matching audio format.');
      },
    }),
  };

  try {
    await assert.rejects(
      () => service.downloadAudio('video-id', directory),
      (error) =>
        error.code === 'DOWNLOAD_UNAVAILABLE' &&
        error.details?.diagnosticStage === 'download.format' &&
        error.details?.errorType === 'Error',
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('reports an unavailable audio format at the format stage', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-download-unavailable-'));
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async () => ({
      chooseFormat: () => null,
    }),
  };

  try {
    await assert.rejects(
      () => service.downloadAudio('video-id', directory),
      (error) =>
        error.code === 'DOWNLOAD_UNAVAILABLE' &&
        error.details?.diagnosticStage === 'download.format',
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('reports an audio stream timeout without retaining a partial download', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'otoha-download-timeout-'));
  const timeout = new Error('Network request timed out.');
  timeout.name = 'TimeoutError';
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getBasicInfo: async () => ({
      chooseFormat: () => ({ mime_type: 'audio/webm; codecs="opus"' }),
      download: async () => {
        throw timeout;
      },
    }),
  };

  try {
    await assert.rejects(
      () => service.downloadAudio('video-id', directory),
      (error) =>
        error.code === 'DOWNLOAD_TIMED_OUT' &&
        error.details?.diagnosticStage === 'download.stream' &&
        error.details?.errorType === 'TimeoutError',
    );
    await assert.rejects(() => readFile(path.join(directory, 'video-id.webm.part')));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('falls back to unsynchronized YouTube Music lyrics', async () => {
  const service = new YouTubeService();
  service.innertube = {
    music: {
      getLyrics: async () => ({
        description: {
          toString: () => 'Official first line\n\nOfficial second line',
        },
      }),
    },
  };

  assert.deepEqual(await service.getLyrics('dQw4w9WgXcQ'), {
    source: 'youtube_music',
    lines: [
      { text: 'Official first line', startSeconds: null },
      { text: 'Official second line', startSeconds: null },
    ],
  });
});

test('treats unavailable YouTube Music lyrics as an empty state', async () => {
  const service = new YouTubeService();
  service.innertube = {
    music: {
      getLyrics: async () => {
        throw new Error('Lyrics are not available.');
      },
    },
  };

  assert.deepEqual(await service.getLyrics('dQw4w9WgXcQ'), {
    source: 'none',
    lines: [],
  });
});

test('prefers cached LRCLIB timing when track metadata matches', async () => {
  const requests = [];
  const service = new YouTubeService({
    fetchImpl: async (url, options) => {
      requests.push({ url: url.toString(), options });
      return {
        ok: true,
        json: async () => ({
          syncedLyrics: '[00:01.25] First line\n[00:03.50][00:04.00] Second line',
        }),
      };
    },
  });

  assert.deepEqual(
    await service.getLyrics('dQw4w9WgXcQ', {
      title: 'Track title',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 213,
    }),
    {
      source: 'lrclib',
      lines: [
        { text: 'First line', startSeconds: 1.25 },
        { text: 'Second line', startSeconds: 3.5 },
        { text: 'Second line', startSeconds: 4 },
      ],
    },
  );
  const url = new URL(requests[0].url);
  assert.equal(url.pathname, '/api/get-cached');
  assert.equal(url.searchParams.get('track_name'), 'Track title');
  assert.equal(url.searchParams.get('duration'), '213');
  assert.equal(requests[0].options.headers['User-Agent'].startsWith('Otoha/'), true);
});

test('uses a timed LRCLIB search result when the exact lookup times out', async () => {
  const service = new YouTubeService({
    fetchImpl: async (url) => {
      if (new URL(url).pathname === '/api/get-cached') {
        const timeout = new Error('Timed out.');
        timeout.name = 'TimeoutError';
        throw timeout;
      }
      return {
        ok: true,
        json: async () => [{ syncedLyrics: '[00:10.00] Fallback line' }],
      };
    },
  });

  assert.deepEqual(
    await service.getLyrics('dQw4w9WgXcQ', {
      title: 'Track title',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 213,
    }),
    {
      source: 'lrclib',
      lines: [{ text: 'Fallback line', startSeconds: 10 }],
    },
  );
});

test('uses LRCLIB exact retrieval when cached and search lookups miss', async () => {
  const requests = [];
  const service = new YouTubeService({
    fetchImpl: async (url) => {
      const request = new URL(url);
      requests.push(request);
      if (request.pathname === '/api/get') {
        return {
          ok: true,
          json: async () => ({ syncedLyrics: '[00:04.50] Retrieved line' }),
        };
      }
      return {
        ok: request.pathname === '/api/search',
        json: async () => [],
      };
    },
  });

  assert.deepEqual(
    await service.getLyrics('dQw4w9WgXcQ', {
      title: 'Track title',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 213,
    }),
    {
      source: 'lrclib',
      lines: [{ text: 'Retrieved line', startSeconds: 4.5 }],
    },
  );
  assert.deepEqual(
    requests.map((request) => request.pathname),
    ['/api/get-cached', '/api/search', '/api/get'],
  );
});

test('searches LRCLIB for timed lyrics after an exact lookup misses', async () => {
  const requests = [];
  const service = new YouTubeService({
    fetchImpl: async (url) => {
      const request = new URL(url);
      requests.push(request);
      if (request.pathname === '/api/get-cached') {
        return { ok: false };
      }
      return {
        ok: true,
        json: async () => [
          { syncedLyrics: '[00:10.00] Timed line' },
          { syncedLyrics: null },
        ],
      };
    },
  });

  assert.deepEqual(
    await service.getLyrics('dQw4w9WgXcQ', {
      title: 'Track title',
      artist: 'Artist',
      album: 'YouTube Music',
      durationSeconds: 213,
    }),
    {
      source: 'lrclib',
      lines: [{ text: 'Timed line', startSeconds: 10 }],
    },
  );
  assert.deepEqual(
    requests.map((request) => request.pathname),
    ['/api/get-cached', '/api/search'],
  );
  assert.equal(requests[1].searchParams.has('album_name'), false);
  assert.equal(requests[1].searchParams.has('duration'), false);
});

test('loads category and dedicated podcast pages through YTMUSIC browse calls', async () => {
  const calls = [];
  const innertube = {
    actions: {
      execute: async (endpoint, args) => {
        calls.push({ endpoint, args });
        if (args.continuation) {
          return {
            success: true,
            status_code: 200,
            data: {
              continuationContents: {
                musicShelfContinuation: {
                contents: [
                  {
                      musicMultiRowListItemRenderer: {
                        title: { runs: [{ text: 'Older episode' }] },
                        subtitle: { runs: [{ text: 'Last week' }] },
                        onTap: {
                          watchEndpoint: {
                            videoId: 'older-podcast-episode-id',
                          },
                        },
                      },
                    },
                ],
                },
              },
            },
          };
        }
        if (args.browseId.startsWith('MPSP')) {
          return {
            success: true,
            status_code: 200,
            data: {
              onResponseReceivedActions: [
                {
                  navigateAction: {
                    endpoint: {
                      commandMetadata: {
                        webCommandMetadata: {
                          apiUrl: '/youtubei/v1/browse',
                        },
                      },
                      browseEndpoint: {
                        browseId: 'VLPLpodcast-show',
                      },
                    },
                  },
                },
              ],
            },
          };
        }
        if (args.browseId === 'VLPLpodcast-show') {
          return {
            success: true,
            status_code: 200,
            data: {
              header: {
                musicResponsiveHeaderRenderer: {
                  title: { runs: [{ text: 'Podcast show' }] },
                  straplineTextOne: {
                    runs: [{ text: 'Podcast publisher' }],
                  },
                  secondSubtitle: { runs: [{ text: '12 episodes' }] },
                  description: {
                    musicDescriptionShelfRenderer: {
                      description: { runs: [{ text: 'Show description' }] },
                    },
                  },
                  thumbnail: {
                    musicThumbnailRenderer: {
                      thumbnail: {
                        thumbnails: [
                          { url: 'podcast-cover', width: 544 },
                        ],
                      },
                    },
                  },
                },
              },
            contents: {
                twoColumnBrowseResultsRenderer: {
                  secondaryContents: {
                    sectionListRenderer: {
                      contents: [
                    {
                          musicCarouselShelfRenderer: {
                            header: {
                              musicCarouselShelfBasicHeaderRenderer: {
                                title: {
                                  runs: [{ text: 'You might also like' }],
                                },
                              },
                            },
                            contents: [
                              {
                                musicResponsiveListItemRenderer: {
                                  flexColumns: [
                                    {
                                      musicResponsiveListItemFlexColumnRenderer: {
                                        text: {
                                          runs: [
                                            { text: 'Wrong recommendation' },
                                          ],
                                        },
                                      },
                                    },
                                  ],
                                  navigationEndpoint: {
                                    watchEndpoint: {
                                      videoId: 'wrong-recommendation',
                                    },
                                  },
                                },
                              },
                            ],
                          },
                        },
                        {
                          musicShelfRenderer: {
                            title: {
                              runs: [{ text: 'Latest episodes' }],
                            },
                            contents: [
                              {
                                musicMultiRowListItemRenderer: {
                                  title: {
                                    runs: [{ text: 'Podcast episode' }],
                                  },
                                  subtitle: { runs: [{ text: 'Today' }] },
                                  secondTitle: {
                                    runs: [{ text: 'Today · 42 min' }],
                                  },
                                  description: {
                                    runs: [{ text: 'Episode description' }],
                                  },
                                  onTap: {
                                    watchEndpoint: {
                                      videoId: 'podcast-episode-id',
                                    },
                                  },
                                },
                              },
                              {
                                continuationItemRenderer: {
                                  continuationEndpoint: {
                                    continuationCommand: {
                                      token: 'podcast-continuation',
                                    },
                                  },
                                },
                              },
                            ],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            },
          };
        }
        return {
          contents: {
            item: () => ({
              tabs: [
                {
                  content: {
                    contents: [
                      {
                        header: { title: 'Artist releases' },
                        contents: [
                          {
                            item_type: 'album',
                            id: 'MPREalbum',
                            title: 'Album',
                          },
                        ],
                      },
                    ],
                  },
                },
              ],
            }),
          },
        };
      },
    },
  };
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = innertube;

  const result = await service.getFeedBrowse(
    'category',
    'FEmusic_moods_and_genres_category',
    'chill-params',
  );

  assert.equal(calls[0].endpoint, 'browse');
  assert.deepEqual(calls[0].args, {
    browseId: 'FEmusic_moods_and_genres_category',
    params: 'chill-params',
    client: 'YTMUSIC',
    parse: true,
  });
  assert.equal(result.sections[0].items[0].itemType, 'album');

  const podcast = await service.getFeedBrowse(
    'podcast',
    'MPSPpodcast-show',
  );
  assert.deepEqual(calls[1].args, {
    browseId: 'MPSPpodcast-show',
    client: 'YTMUSIC',
  });
  assert.deepEqual(calls[2], {
    endpoint: 'browse',
    args: {
      browseId: 'VLPLpodcast-show',
      client: 'YTMUSIC',
    },
  });
  assert.deepEqual(podcast, {
    podcast: {
      id: 'MPSPpodcast-show',
      libraryId: 'PLpodcast-show',
      title: 'Podcast show',
      subtitle: 'Podcast publisher',
      description: 'Show description',
      thumbnailUrl: 'podcast-cover',
      episodes: [
        {
          id: 'podcast-episode-id',
          itemType: 'episode',
          title: 'Podcast episode',
          subtitle: 'Today · 42 min',
          videoId: 'podcast-episode-id',
          artists: [],
          album: null,
          durationSeconds: 2520,
          thumbnailUrl: null,
          description: 'Episode description',
        },
      ],
      hasMore: true,
    },
  });
  assert.equal(
    podcast.podcast.episodes.some((item) => item.id === 'wrong-recommendation'),
    false,
  );

  assert.deepEqual(
    await service.getMoreFeedBrowse('podcast', 'MPSPpodcast-show'),
    {
      episodes: [
        {
          id: 'older-podcast-episode-id',
          itemType: 'episode',
          title: 'Older episode',
          subtitle: 'Last week',
          videoId: 'older-podcast-episode-id',
          artists: [],
          album: null,
          durationSeconds: 0,
          thumbnailUrl: null,
          description: null,
        },
      ],
      hasMore: false,
    },
  );
  assert.deepEqual(calls[3], {
    endpoint: '/browse',
    args: {
      client: 'YTMUSIC',
      continuation: 'podcast-continuation',
    },
  });
});

test('maps playlist-style podcast episode shelves from raw browse JSON', () => {
  const result = mapRawPodcastShowDetail({
    header: {
      musicDetailHeaderRenderer: {
        title: { runs: [{ text: 'Playlist podcast' }] },
      },
    },
    contents: {
      singleColumnBrowseResultsRenderer: {
        tabs: [
          {
            tabRenderer: {
              content: {
                sectionListRenderer: {
                  contents: [
                    {
                      musicPlaylistShelfRenderer: {
                        contents: [
                          {
                            musicResponsiveListItemRenderer: {
                              flexColumns: [
                                {
                                  musicResponsiveListItemFlexColumnRenderer: {
                                    text: {
                                      runs: [{ text: 'Playlist episode' }],
                                    },
                                  },
                                },
                                {
                                  musicResponsiveListItemFlexColumnRenderer: {
                                    text: {
                                      runs: [
                                        { text: 'June 19 · 25 minutes' },
                                      ],
                                    },
                                  },
                                },
                              ],
                              playlistItemData: {
                                videoId: 'playlist-episode-id',
                              },
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        ],
      },
    },
  });

  assert.equal(result.title, 'Playlist podcast');
  assert.deepEqual(result.episodes, [
    {
      id: 'playlist-episode-id',
      itemType: 'episode',
      title: 'Playlist episode',
      subtitle: 'June 19 · 25 minutes',
      videoId: 'playlist-episode-id',
      artists: [],
      album: null,
      durationSeconds: 1500,
      thumbnailUrl: null,
      description: null,
    },
  ]);
});

test('maps and submits authenticated track interactions without exposing input', async () => {
  const calls = [];
  let now = 0;
  const service = new YouTubeService({ now: () => now });
  service.authMode = 'cookie';
  service.innertube = {
    interact: {
      like: async (videoId) => calls.push(['rating', 'like', videoId]),
      dislike: async (videoId) => calls.push(['rating', 'dislike', videoId]),
      removeRating: async (videoId) =>
        calls.push(['rating', 'none', videoId]),
      comment: async (videoId, text) => calls.push(['comment', videoId, text]),
    },
    getComments: async () => ({
      contents: [
        {
          comment: {
            comment_id: 'comment-id',
            author: {
              name: 'Listener',
              thumbnails: [{ url: 'avatar', width: 64 }],
            },
            content: { toString: () => 'Great track' },
            published_time: { toString: () => '1 hour ago' },
            like_count: '7',
          },
        },
      ],
      has_continuation: true,
    }),
  };

  assert.deepEqual(await service.rateVideo('video-id', 'like'), { rating: 'like' });
  now += 2000;
  assert.deepEqual(await service.rateVideo('video-id', 'dislike'), { rating: 'dislike' });
  now += 2000;
  assert.deepEqual(await service.rateVideo('video-id', 'none'), { rating: 'none' });
  now += 2000;
  assert.deepEqual(await service.getComments('video-id'), {
    comments: [
      {
        id: 'comment-id',
        author: 'Listener',
        text: 'Great track',
        publishedTime: '1 hour ago',
        avatarUrl: 'avatar',
        likeCount: '7',
      },
    ],
    hasMore: true,
    commentsAvailable: true,
  });
  assert.deepEqual(await service.createComment('video-id', ' Nice track '), {
    posted: true,
  });
  assert.deepEqual(calls, [
    ['rating', 'like', 'video-id'],
    ['rating', 'dislike', 'video-id'],
    ['rating', 'none', 'video-id'],
    ['comment', 'video-id', 'Nice track'],
  ]);
  assert.equal(mapCommentThread({ comment: {} }), null);
});

test('falls back to web video controls when generic rating actions are unavailable', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    interact: {
      like: async () => {
        throw new Error('TV actions unavailable');
      },
    },
    getInfo: async (videoId, options) => {
      calls.push(['getInfo', videoId, options.client]);
      return {
        like: async () => calls.push(['like', videoId]),
      };
    },
  };

  assert.deepEqual(await service.rateVideo('video-id', 'like'), {
    rating: 'like',
  });
  assert.deepEqual(calls, [
    ['getInfo', 'video-id', 'WEB'],
    ['like', 'video-id'],
  ]);
});

test('updates artist, episode, and podcast-show account state', async () => {
  const calls = [];
  let now = 0;
  let subscribed = false;
  const service = new YouTubeService({ now: () => now });
  service.authMode = 'cookie';
  service.innertube = {
    music: {
      getArtist: async () => ({
        header: {
          subscription_button: {
            channel_id: 'UCcanonical-artist',
            subscribed,
            on_subscribe_endpoints: [
              {
                call: async (_actions, options) => {
                  calls.push(['subscribe', 'UCcanonical-artist', options.client]);
                  subscribed = true;
                },
              },
            ],
            on_unsubscribe_endpoints: [
              {
                call: async (_actions, options) => {
                  calls.push([
                    'unsubscribe',
                    'UCcanonical-artist',
                    options.client,
                  ]);
                  subscribed = false;
                },
              },
            ],
          },
        },
      }),
    },
    actions: {
      execute: async (endpoint, payload) => {
        calls.push(['execute', endpoint, payload]);
        return {
          success: true,
          status_code: 200,
          data: { status: 'STATUS_SUCCEEDED' },
        };
      },
    },
    playlist: {
      addVideos: async (playlistId, videoIds) => {
        calls.push(['addVideos', playlistId, videoIds]);
      },
      addToLibrary: async (podcastId) => {
        calls.push(['addToLibrary', podcastId]);
      },
      removeFromLibrary: async (podcastId) => {
        calls.push(['removeFromLibrary', podcastId]);
      },
    },
  };

  assert.deepEqual(await service.setSubscription('channel-id', true), {
    subscribed: true,
    channelId: 'UCcanonical-artist',
  });
  now += 2000;
  assert.deepEqual(await service.setSubscription('channel-id', false), {
    subscribed: false,
    channelId: 'UCcanonical-artist',
  });
  now += 2000;
  service.playlistPages.set('SE', {});
  assert.deepEqual(await service.setEpisodeForLater('video-id', true), {
    saved: true,
  });
  assert.equal(service.playlistPages.has('SE'), false);
  now += 2000;
  service.playlistPages.set('SE', {});
  assert.deepEqual(await service.setEpisodeForLater('video-id', false), {
    saved: false,
  });
  assert.equal(service.playlistPages.has('SE'), false);
  now += 2000;
  assert.deepEqual(await service.setPodcastInLibrary('MPSPshow', true), {
    saved: true,
  });
  now += 2000;
  assert.deepEqual(await service.setPodcastInLibrary('MPSPshow', false), {
    saved: false,
  });
  assert.deepEqual(calls, [
    ['subscribe', 'UCcanonical-artist', 'YTMUSIC'],
    ['unsubscribe', 'UCcanonical-artist', 'YTMUSIC'],
    ['addVideos', 'SE', ['video-id']],
    [
      'execute',
      'browse/edit_playlist',
      {
        playlistId: 'SE',
        actions: [
          {
            action: 'ACTION_REMOVE_VIDEO_BY_VIDEO_ID',
            removedVideoId: 'video-id',
          },
        ],
        client: 'YTMUSIC',
      },
    ],
    ['addToLibrary', 'MPSPshow'],
    ['removeFromLibrary', 'MPSPshow'],
  ]);
});

test('retries podcast library manager HTTP 400 with canonical request bodies', async () => {
  const calls = [];
  let now = 0;
  const service = new YouTubeService({ now: () => now });
  service.authMode = 'cookie';
  service.innertube = {
    playlist: {
      addToLibrary: async (podcastId) => {
        calls.push(['addToLibrary', podcastId]);
        const error = new Error('Request failed with status 400.');
        error.statusCode = 400;
        throw error;
      },
      removeFromLibrary: async (podcastId) => {
        calls.push(['removeFromLibrary', podcastId]);
        return { success: false, status_code: 400 };
      },
    },
    actions: {
      execute: async (endpoint, payload) => {
        calls.push(['execute', endpoint, payload]);
        return { success: true, status_code: 200 };
      },
    },
  };

  assert.deepEqual(
    await service.setPodcastInLibrary('VLPLpodcast-show', true),
    { saved: true },
  );
  now += 2000;
  assert.deepEqual(
    await service.setPodcastInLibrary('PLpodcast-show', false),
    { saved: false },
  );
  assert.deepEqual(calls, [
    ['addToLibrary', 'PLpodcast-show'],
    [
      'execute',
      'like/like',
      {
        target: { playlistId: 'PLpodcast-show' },
        client: 'YTMUSIC',
      },
    ],
    ['removeFromLibrary', 'PLpodcast-show'],
    [
      'execute',
      'like/removelike',
      {
        target: { playlistId: 'PLpodcast-show' },
        client: 'YTMUSIC',
      },
    ],
  ]);
});

test('reports a failed saved-episode playlist update', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    playlist: {
      addVideos: async () => {
        const error = new Error('Saved episode update failed.');
        error.code = 'STATUS_FAILED';
        throw error;
      },
    },
  };

  await assert.rejects(service.setEpisodeForLater('video-id', true), (error) => {
    const serialized = serializeError(error);
    assert.equal(serialized.code, 'SAVED_EPISODE_UPDATE_FAILED');
    assert.equal(serialized.details.diagnosticStage, 'saved_episode.update');
    assert.equal(serialized.details.upstreamCode, 'STATUS_FAILED');
    return true;
  });
});

test('reports a failed direct saved-episode removal', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    actions: {
      execute: async () => ({ success: false, status_code: 500 }),
    },
  };

  await assert.rejects(service.setEpisodeForLater('video-id', false), (error) => {
    const serialized = serializeError(error);
    assert.equal(serialized.code, 'SAVED_EPISODE_UPDATE_FAILED');
    assert.equal(serialized.details.diagnosticStage, 'saved_episode.update');
    assert.equal(serialized.details.statusCode, 500);
    return true;
  });
});

test('reports a failed podcast-show library update', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    playlist: {
      addToLibrary: async () => {
        const error = new Error('Podcast library update failed.');
        error.code = 'STATUS_FAILED';
        throw error;
      },
    },
  };

  await assert.rejects(
    service.setPodcastInLibrary('MPSPshow', true),
    (error) => {
      const serialized = serializeError(error);
      assert.equal(serialized.code, 'PODCAST_LIBRARY_UPDATE_FAILED');
      assert.equal(
        serialized.details.diagnosticStage,
        'podcast.library.update',
      );
      assert.equal(serialized.details.upstreamCode, 'STATUS_FAILED');
      return true;
    },
  );
});

test('does not fall back to a generic Web subscription request', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    interact: {
      subscribe: async () => {
        throw new Error('The generic endpoint must not be used.');
      },
    },
    music: {
      getArtist: async () => ({
        header: {
          subscription_button: {
            channel_id: 'UCcanonical-artist',
            subscribed: false,
            on_subscribe_endpoints: [
              {
                call: async () => ({ success: false, status_code: 400 }),
              },
            ],
          },
        },
      }),
    },
    actions: {
      execute: async () => {
        throw new Error('The generic Web fallback must not be used.');
      },
    },
  };

  await assert.rejects(
    () => service.setSubscription('UCrequested-artist', true),
    (error) =>
      error.code === 'SUBSCRIPTION_UPDATE_FAILED' &&
      error.details.diagnosticStage === 'subscription.update' &&
      error.details.statusCode === 400,
  );
});

test('uses the artist page subscription action and canonical channel ID', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    music: {
      getArtist: async (requestedChannelId) => ({
        header: {
          subscription_button: {
            channel_id: 'UCcanonical-artist',
            subscribed: false,
            on_subscribe_endpoints: [
              {
                call: async (_actions, options) =>
                  calls.push([requestedChannelId, options.client]),
              },
            ],
          },
        },
      }),
    },
    actions: {},
  };

  assert.deepEqual(await service.setSubscription('UCchannel-id', true), {
    subscribed: true,
    channelId: 'UCcanonical-artist',
  });
  assert.deepEqual(calls, [['UCchannel-id', 'YTMUSIC']]);
});

test('refreshes the raw artist page when the parsed header omits its action', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    music: {
      getArtist: async () => ({
        header: {
          subscription_button: {
            channel_id: 'UCcanonical-artist',
            subscribed: false,
          },
        },
      }),
    },
    actions: {
      execute: async (endpoint, args) => {
        calls.push([endpoint, args]);
        if (endpoint === 'browse') {
          return {
            success: true,
            status_code: 200,
            data: {
              header: {
                musicImmersiveHeaderRenderer: {
                  title: { simpleText: 'Fresh artist' },
                  subscriptionButton: {
                    subscribeButtonRenderer: {
                      channelId: 'UCcanonical-artist',
                      subscribed: false,
                      onSubscribeEndpoints: [
                        {
                          subscribeEndpoint: {
                            channelIds: ['UCcanonical-artist'],
                            params: 'artist-subscription-token',
                          },
                        },
                      ],
                    },
                  },
                },
              },
            },
          };
        }
        return { success: true, status_code: 200 };
      },
    },
  };

  assert.deepEqual(await service.setSubscription('UCcanonical-artist', true), {
    subscribed: true,
    channelId: 'UCcanonical-artist',
  });
  assert.deepEqual(calls, [
    [
      'browse',
      {
        browseId: 'UCcanonical-artist',
        client: 'YTMUSIC',
      },
    ],
    [
      'subscription/subscribe',
      {
        channelIds: ['UCcanonical-artist'],
        params: 'artist-subscription-token',
        client: 'YTMUSIC',
      },
    ],
  ]);
});

test('uses the canonical YT Music subscription request when artist actions are absent', async () => {
  const calls = [];
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    interact: {
      subscribe: async () => {
        throw new Error('The generic interaction client must not be used.');
      },
    },
    music: {
      getArtist: async () => ({
        header: {
          subscription_button: {
            channel_id: 'UCcanonical-artist',
            subscribed: false,
          },
        },
      }),
    },
    actions: {
      execute: async (endpoint, args) => {
        calls.push([endpoint, args]);
        if (endpoint === 'browse') {
          return {
            success: true,
            status_code: 200,
            data: {
              header: {
                musicImmersiveHeaderRenderer: {
                  title: { simpleText: 'Fresh artist' },
                  subscriptionButton: {
                    subscribeButtonRenderer: {
                      channelId: 'UCcanonical-artist',
                      subscribed: false,
                    },
                  },
                },
              },
            },
          };
        }
        return { success: true, status_code: 200 };
      },
    },
  };

  assert.deepEqual(await service.setSubscription('UCcanonical-artist', true), {
    subscribed: true,
    channelId: 'UCcanonical-artist',
  });
  assert.deepEqual(calls, [
    [
      'browse',
      {
        browseId: 'UCcanonical-artist',
        client: 'YTMUSIC',
      },
    ],
    [
      'subscription/subscribe',
      {
        channelIds: ['UCcanonical-artist'],
        params: 'EgIIAhgA',
        client: 'YTMUSIC',
      },
    ],
  ]);
});

test('treats comments disabled by a track as an empty comments list', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getComments: async () => {
      throw new Error('Comments are disabled.');
    },
  };

  assert.deepEqual(await service.getComments('video-id'), {
    comments: [],
    hasMore: false,
    commentsAvailable: false,
  });
});

test('throttles rapid authenticated account writes', async () => {
  const service = new YouTubeService({ now: () => 1000 });
  service.authMode = 'cookie';
  service.innertube = {
    actions: { execute: async () => {} },
    interact: {
      like: async () => {},
      comment: async () => {},
    },
  };

  await service.rateVideo('video-id', 'like');
  await assert.rejects(
    () => service.createComment('video-id', 'Too soon'),
    (error) => error.code === 'ACCOUNT_WRITE_THROTTLED',
  );
});

test('stops when a playlist continuation repeats the same page', async () => {
  const repeatedPage = {
    items: [
      {
        item_type: 'song',
        id: 'same-track',
        title: 'Same track',
        artists: [],
        duration: { seconds: 60 },
      },
    ],
    has_continuation: true,
  };
  repeatedPage.getContinuation = async () => repeatedPage;
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    music: { getPlaylist: async () => repeatedPage },
  };

  const result = await service.getFeedCollection('playlist', 'PL1');

  assert.equal(result.tracks.length, 1);
});

function expectEqual(actual, expected) {
  assert.deepEqual(actual, expected);
}
