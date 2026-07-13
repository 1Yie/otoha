import assert from 'node:assert/strict';
import test from 'node:test';

import {
  mapBrowseFeedSections,
  mapAccountProfile,
  mapFeedSections,
  mapSearchItems,
  mapPlaylist,
  mapTrack,
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
      thumbnail: { contents: [{ url: 'cover', width: 256 }] },
    }),
    {
      videoId: 'video-id',
      title: 'Track title',
      artists: ['Artist'],
      album: 'Album',
      durationSeconds: 183,
      thumbnailUrl: 'cover',
    },
  );
});

test('maps the active account name and avatar from a Cookie session', () => {
  const text = (value) => ({ toString: () => value });
  assert.deepEqual(
    mapAccountProfile({
      contents: {
        contents: [
          {
            account_name: text('Otoha listener'),
            account_photo: [
              { url: 'small-avatar', width: 48 },
              { url: 'large-avatar', width: 256 },
            ],
          },
        ],
      },
    }),
    { displayName: 'Otoha listener', avatarUrl: 'large-avatar' },
  );
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
    account: { getInfo: async () => ({}) },
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

test('loads Home and Explore through the music client', async () => {
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
  const innertube = {
    session,
    music: {
      getHomeFeed: async () => ({ sections: [section] }),
      getExplore: async () => ({ sections: [section] }),
    },
  };
  const service = new YouTubeService({ createInnertube: async () => innertube });
  service.innertube = innertube;

  assert.equal((await service.getHomeFeed()).sections[0].title, 'Recommendations');
  assert.equal((await service.getExploreFeed()).sections[0].items[0].id, 'PL1');
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
  service.innertube = {
    music: { getPlaylist: async () => repeatedPage },
  };

  const result = await service.getFeedCollection('playlist', 'PL1');

  assert.equal(result.tracks.length, 1);
});

function expectEqual(actual, expected) {
  assert.deepEqual(actual, expected);
}
