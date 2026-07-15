import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  mapBrowseFeedSections,
  mapAccountProfile,
  mapCommentThread,
  mapFeedSections,
  mapSearchItems,
  mapPlaylist,
  mapTrack,
  serializeError,
  YouTubeService,
} from '../src/youtube_service.mjs';

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
      title: 'Track title',
      artists: ['Artist'],
      album: 'Album',
      durationSeconds: 183,
      thumbnailUrl:
        'https://lh3.googleusercontent.com/cover=w1200-h1200-l90-rj',
    },
  );
});

test('maps the active account name and avatar from a Cookie session', () => {
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
        account_photo: [
          { url: 'small-avatar', width: 48 },
          { url: 'large-avatar', width: 256 },
        ],
        is_selected: true,
      },
    ]),
    { displayName: 'Otoha listener', avatarUrl: 'large-avatar' },
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

test('filters podcast episodes out of music feed sections', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapFeedSections([
      {
        header: { title: text('Popular episodes') },
        contents: [
          {
            constructor: { type: 'MusicMultiRowListItem' },
            title: text('Podcast episode'),
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
    ],
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
    () => service.getFeedBrowse('artist', 'UCartist'),
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
  assert.deepEqual(result.tracks.map((item) => item.videoId), ['first', 'second']);
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
  const initialExploreFeed = {
    sections: [section],
    page: {
      contents: {
        item: () => ({
          as: () => ({
            tabs: [
              {
                selected: true,
                content: { as: () => ({ continuation: 'explore-token' }) },
              },
            ],
          }),
        }),
      },
    },
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
      getExplore: async () => initialExploreFeed,
    },
    actions: {
      execute: async (endpoint, args) => {
        assert.equal(endpoint, '/browse');
        assert.equal(args.client, 'YTMUSIC');
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
  assert.equal(explore.sections[0].items[0].id, 'PL1');
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

test('loads authenticated YouTube Music history as playable tracks', async () => {
  const historyItem = {
    constructor: { type: 'Video' },
    id: 'history-video',
    title: { toString: () => 'History track' },
    author: { name: 'History artist' },
    duration: { seconds: 213 },
    thumbnails: [{ url: 'https://example.test/history.jpg' }],
  };
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    actions: {
      execute: async (endpoint, params) => {
        assert.equal(endpoint, '/browse');
        assert.deepEqual(params, {
          browseId: 'FEmusic_history',
          client: 'YTMUSIC',
          parse: true,
        });
        return {
          contents_memo: {
            getType: () => [{ contents: [historyItem, historyItem] }],
          },
        };
      },
    },
  };

  const result = await service.getHistory();

  assert.deepEqual(result.tracks, [
    {
      videoId: 'history-video',
      title: 'History track',
      artists: ['History artist'],
      album: null,
      durationSeconds: 213,
      thumbnailUrl: 'https://example.test/history.jpg',
    },
  ]);
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
      getAlbum: async () => ({ contents: [track('album-track')] }),
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
  assert.deepEqual(
    (await service.getFeedCollection('playlist', 'PL1')).tracks.map(
      (item) => item.videoId,
    ),
    ['playlist-track'],
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
    getStreamingData: async (videoId, options) => {
      calls.push({ videoId, options });
      return {
        url: 'https://audio.example.test/stream?token=short-lived',
        mime_type: 'audio/webm; codecs="opus"',
        bitrate: 128000,
        approx_duration_ms: 213000,
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
    },
  });
  assert.deepEqual(calls, [
    {
      videoId: 'video-id',
      options: {
        client: 'YTMUSIC',
        type: 'audio',
        quality: 'best',
        format: 'any',
      },
    },
  ]);
  assert.equal(JSON.stringify(result).includes('SID='), false);
});

test('does not expose the upstream failure when audio playback cannot resolve', async () => {
  const service = new YouTubeService();
  service.authMode = 'cookie';
  service.innertube = {
    getStreamingData: async () => {
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

test('loads artist and category browse pages through a YTMUSIC browse call', async () => {
  const calls = [];
  const innertube = {
    actions: {
      execute: async (endpoint, args) => {
        calls.push({ endpoint, args });
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
