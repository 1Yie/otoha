import { Innertube, UniversalCache } from 'youtubei.js';

const MAX_LIBRARY_PAGES = 50;
const MAX_PLAYLIST_PAGES = 100;

export class YouTubeService {
  constructor({ createInnertube = createDefaultInnertube, emit = () => {} } = {}) {
    this.createInnertube = createInnertube;
    this.emit = emit;
    this.innertube = null;
    this.authMode = null;
    this.profile = null;
  }

  async restore(credential) {
    if (!credential) {
      await this.#createSession();
      return { authenticated: false };
    }

    if (credential.kind !== 'cookie') {
      throw new SidecarError('INVALID_CREDENTIAL', 'Unsupported saved credential.');
    }
    return this.signInWithCookie(credential.value);
  }

  async signInWithCookie(cookie) {
    const value = typeof cookie === 'string' ? cookie.trim() : '';
    if (!value) {
      throw new SidecarError('INVALID_COOKIE', 'A YouTube Cookie header is required.');
    }

    await this.#createSession(value);
    this.profile = mapAccountProfile(await this.innertube.account.getInfo());
    this.authMode = 'cookie';
    this.emit('auth.credentials', {
      credential: { kind: 'cookie', value },
    });
    return { authenticated: true, mode: this.authMode, profile: this.profile };
  }

  async signOut() {
    await this.#createSession();
    this.authMode = null;
    this.profile = null;
    return { authenticated: false };
  }

  status() {
    return {
      authenticated: this.authMode === 'cookie',
      mode: this.authMode,
      profile: this.profile,
    };
  }

  async getLibraryPlaylists() {
    this.#requireAuthentication();

    let page = await this.innertube.music.getLibrary();
    if (page.filters?.includes('Playlists')) {
      page = await page.applyFilter('Playlists');
    }

    const playlists = [];
    const seen = new Set();
    for (let index = 0; index < MAX_LIBRARY_PAGES && page; index += 1) {
      for (const item of collectItems(page.contents)) {
        const playlist = mapPlaylist(item);
        if (playlist && !seen.has(playlist.id)) {
          playlists.push(playlist);
          seen.add(playlist.id);
        }
      }
      page = page.has_continuation ? await page.getContinuation() : null;
    }
    return { playlists };
  }

  async getPlaylist(playlistId) {
    this.#requireAuthentication();
    const id = normalizePlaylistId(playlistId);
    if (!id) {
      throw new SidecarError('INVALID_PLAYLIST_ID', 'A playlist ID is required.');
    }

    let page = await this.innertube.music.getPlaylist(id);
    const playlist = mapPlaylistHeader(id, page.header, page.background);
    const tracks = [];
    const seenPages = new Set();
    for (let index = 0; index < MAX_PLAYLIST_PAGES && page; index += 1) {
      const pageTracks = (page.items ?? []).map(mapTrack).filter(Boolean);
      if (!appendUniquePage(tracks, pageTracks, seenPages)) break;
      page = page.has_continuation ? await page.getContinuation() : null;
    }
    return { playlist, tracks };
  }

  async getHomeFeed() {
    const feed = await this.innertube.music.getHomeFeed();
    return { sections: mapFeedSections(feed.sections) };
  }

  async getExploreFeed() {
    const feed = await this.innertube.music.getExplore();
    return { sections: mapFeedSections(feed.sections) };
  }

  async searchMusic(query) {
    if (typeof query !== 'string' || !query.trim()) {
      return { items: [] };
    }
    const search = await this.innertube.music.search(query.trim());
    return { items: mapSearchItems(search.contents) };
  }

  async getFeedCollection(itemType, id) {
    if (!['playlist', 'album'].includes(itemType) || !id) {
      throw new SidecarError(
        'INVALID_FEED_ITEM',
        'Only playlist and album feed items can be loaded as a collection.',
      );
    }

    if (itemType === 'album') {
      const album = await this.innertube.music.getAlbum(id);
      return { tracks: album.contents.map(mapTrack).filter(Boolean) };
    }

    let page = await this.innertube.music.getPlaylist(id);
    const tracks = [];
    const seenPages = new Set();
    for (let index = 0; index < MAX_PLAYLIST_PAGES && page; index += 1) {
      const pageTracks = (page.items ?? []).map(mapTrack).filter(Boolean);
      if (!appendUniquePage(tracks, pageTracks, seenPages)) break;
      page = page.has_continuation ? await page.getContinuation() : null;
    }
    return { tracks };
  }

  async getFeedTrack(videoId) {
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to load track metadata.',
      );
    }

    const info = await this.innertube.getBasicInfo(videoId, {
      client: 'YTMUSIC',
    });
    const basicInfo = info?.basic_info;
    const title = textValue(basicInfo?.title);
    if (!title) {
      throw new SidecarError(
        'TRACK_METADATA_UNAVAILABLE',
        'YouTube did not return track metadata for this item.',
      );
    }
    const artist = textValue(basicInfo?.author?.name ?? basicInfo?.author);
    return {
      track: {
        videoId: basicInfo?.id ?? videoId,
        title,
        artists: artist ? [artist] : [],
        durationSeconds: Number.isInteger(basicInfo?.duration)
          ? basicInfo.duration
          : 0,
        thumbnailUrl: largestThumbnail(arrayOf(basicInfo?.thumbnail))?.url ?? null,
      },
    };
  }

  async getFeedBrowse(itemType, id, params) {
    if (!['artist', 'category', 'channel', 'subscriber'].includes(itemType) || !id) {
      throw new SidecarError(
        'INVALID_FEED_ITEM',
        'Only artist, channel, or category feed items can be opened as browse pages.',
      );
    }

    const page = await this.innertube.actions.execute('browse', {
      browseId: id,
      ...(params ? { params } : {}),
      client: 'YTMUSIC',
      parse: true,
    });
    return { sections: mapBrowseFeedSections(page) };
  }

  async #createSession(cookie) {
    this.innertube = await this.createInnertube(cookie);
    this.authMode = cookie ? 'cookie' : null;
  }

  #requireAuthentication() {
    if (this.authMode !== 'cookie') {
      throw new SidecarError('AUTH_REQUIRED', 'Sign in before loading your library.');
    }
  }
}

async function createDefaultInnertube(cookie) {
  return Innertube.create({
    cookie,
    cache: new UniversalCache(false),
    lang: 'en',
    device_category: 'DESKTOP',
    generate_session_locally: true,
    retrieve_player: false,
    retrieve_innertube_config: false,
  });
}

export function mapPlaylist(item) {
  const type = item?.type ?? item?.constructor?.type ?? item?.constructor?.name;
  const itemType = item?.item_type ?? item?.content_type?.toLowerCase();
  if (
    itemType && itemType !== 'playlist' ||
    !itemType && !['GridPlaylist', 'LockupView', 'MusicTwoRowItem', 'MusicResponsiveListItem'].includes(type)
  ) {
    return null;
  }

  const id = normalizePlaylistId(
    item?.id ?? item?.content_id ?? item?.endpoint?.payload?.browseId,
  );
  const title = textValue(item?.title ?? item?.metadata?.title);
  if (!id || !title) return null;

  return {
    id,
    title,
    owner: item?.author?.name ?? metadataText(item?.metadata?.metadata),
    itemCount: textValue(item?.video_count ?? item?.item_count),
    thumbnailUrl: largestThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

export function mapTrack(item) {
  const type = item?.type ?? item?.constructor?.type ?? item?.constructor?.name;
  const itemType = item?.item_type ?? item?.content_type?.toLowerCase();
  if (
    !item ||
    !['song', 'video', 'non_music_track'].includes(itemType) &&
      !['PlaylistVideo', 'LockupView'].includes(type)
  ) {
    return null;
  }
  const videoId = item.id ?? item.content_id ?? item.endpoint?.payload?.videoId;
  const title = textValue(item.title ?? item.metadata?.title);
  if (!videoId || !title) return null;

  const subtitle = textValue(item.subtitle ?? item.second_title ?? item.description);
  const artists = item.artists ?? item.authors ?? (item.author ? [item.author] : []);
  const artistNames = artists
    .map((artist) => textValue(artist?.name ?? artist))
    .filter(Boolean);
  return {
    videoId,
    title,
    artists: artistNames.length ? artistNames : artistsFromSubtitle(subtitle),
    album: textValue(item.album?.name ?? item.album) ?? albumFromSubtitle(subtitle),
    durationSeconds: item.duration?.seconds ?? 0,
    thumbnailUrl: largestThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

export function mapFeedSections(rawSections) {
  return arrayOf(rawSections)
    .map((section, sectionIndex) => {
      const title = textValue(section?.header?.title);
      const items = arrayOf(section?.contents)
        .map((item, itemIndex) => mapFeedItem(item, sectionIndex, itemIndex))
        .filter(Boolean);
      return title && items.length ? { title, items } : null;
    })
    .filter(Boolean);
}

export function mapSearchItems(rawSections) {
  const seen = new Set();
  return collectItems(arrayOf(rawSections))
    .map((item, index) => mapFeedItem(item, 0, index))
    .filter((item) => {
      if (!item) return false;
      if (['non_music_track', 'unknown'].includes(item.itemType)) return false;
      const key = `${item.itemType}:${item.id}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 40);
}

export function mapBrowseFeedSections(page) {
  const root = page?.contents?.item?.();
  const tabs = arrayOf(root?.tabs);
  const tab = tabs.find((candidate) => candidate?.selected) ?? tabs[0];
  return mapFeedSections(tab?.content?.contents);
}

export function mapFeedItem(item, sectionIndex = 0, itemIndex = 0) {
  if (!item) return null;
  const nodeType = item?.type ?? item?.constructor?.type ?? item?.constructor?.name;
  const endpoint = item?.endpoint ?? item?.on_tap;
  const payload = endpoint?.payload ?? {};
  const inferredType = feedItemType(nodeType, payload);
  const explicitType = normalizeFeedItemType(
    item?.item_type ?? item?.content_type,
  );
  const itemType =
    explicitType &&
      !(
        isTrackItemType(explicitType) &&
        !payload.videoId &&
        payload.browseId &&
        inferredType !== 'unknown'
      )
      ? explicitType
      : inferredType;
  if (itemType === 'episode') return null;
  const rawId = item?.id ?? item?.content_id ?? payload.browseId ?? payload.videoId;
  const id = itemType === 'playlist' ? normalizePlaylistId(rawId) : rawId;
  const title = textValue(item?.title ?? item?.name ?? item?.button_text);
  if (!title) return null;

  const artists = item?.artists ?? item?.authors ?? (item?.author ? [item.author] : []);
  const artistNames = artists
    .map((artist) => textValue(artist?.name ?? artist))
    .filter(Boolean);
  const subtitle = textValue(
    item?.subtitle ?? item?.second_title ?? item?.description,
  ) ?? artistNames.join(' · ');
  const resolvedArtists = artistNames.length
    ? artistNames
    : artistsFromSubtitle(subtitle);

  return {
    id: id || `${itemType}-${sectionIndex}-${itemIndex}`,
    itemType,
    title,
    subtitle: subtitle || null,
    videoId: isTrackItemType(itemType)
      ? item?.id ?? payload.videoId ?? null
      : null,
    ...(typeof payload.params === 'string' ? { browseParams: payload.params } : {}),
    artists: resolvedArtists,
    album: textValue(item?.album?.name ?? item?.album) ?? albumFromSubtitle(subtitle),
    durationSeconds: item?.duration?.seconds ?? 0,
    thumbnailUrl: largestThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

function mapPlaylistHeader(id, rawHeader, background) {
  const header = rawHeader?.header ?? rawHeader;
  return {
    id,
    title: textValue(header?.title) || 'Playlist',
    owner: header?.author?.name ?? textValue(header?.strapline_text_one),
    itemCount: header?.song_count ?? header?.total_items ?? textValue(header?.second_subtitle),
    description: textValue(header?.description),
    thumbnailUrl: largestThumbnail([
      ...thumbnailCandidates(header),
      ...thumbnailCandidates(background),
    ])?.url ?? null,
  };
}

function collectItems(sections) {
  const items = [];
  const source = sections && typeof sections[Symbol.iterator] === 'function'
    ? sections
    : sections ? [sections] : [];
  for (const section of source) {
    const children = section?.contents ?? section?.items ?? [];
    if (Array.isArray(children) || typeof children?.[Symbol.iterator] === 'function') {
      items.push(...children);
    }
  }
  return items;
}

function thumbnailCandidates(item) {
  return [
    ...arrayOf(item?.contents),
    ...arrayOf(item?.thumbnails),
    ...arrayOf(item?.thumbnail),
    ...arrayOf(item?.thumbnail?.contents),
    ...arrayOf(item?.thumbnail?.image),
    ...arrayOf(item?.content_image?.image),
    ...arrayOf(item?.content_image?.primary_thumbnail?.image),
    ...arrayOf(item?.background?.contents),
  ];
}

function arrayOf(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value;
  if (typeof value[Symbol.iterator] === 'function') return [...value];
  return value.url ? [value] : [];
}

function largestThumbnail(thumbnails) {
  return thumbnails
    .filter((thumbnail) => thumbnail?.url)
    .sort((a, b) => (b.width ?? 0) - (a.width ?? 0))[0];
}

function textValue(value) {
  if (!value) return null;
  if (typeof value === 'string') return value;
  if (typeof value.text === 'string') return value.text;
  if (typeof value.toString === 'function') {
    const text = value.toString();
    return text === '[object Object]' ? null : text;
  }
  return null;
}

function metadataText(metadata) {
  if (!metadata) return null;
  const rows = metadata.metadata_rows ?? metadata.rows ?? [];
  return textValue(rows[0]?.metadata_parts?.[0]?.text);
}

function artistsFromSubtitle(subtitle) {
  if (typeof subtitle !== 'string') return [];
  const parts = subtitle.split(' • ').map((part) => part.trim()).filter(Boolean);
  return parts.length > 1 ? parts.slice(1) : [];
}

function albumFromSubtitle(subtitle) {
  if (typeof subtitle !== 'string') return null;
  const parts = subtitle.split(' • ').map((part) => part.trim()).filter(Boolean);
  return parts.length > 1 ? parts[0] ?? null : null;
}

export function mapAccountProfile(accountInfo) {
  const account = arrayOf(accountInfo?.contents?.contents).find(
    (item) => item?.account_name,
  );
  if (!account) return null;
  const displayName = textValue(account.account_name);
  const avatarUrl = largestThumbnail(arrayOf(account.account_photo))?.url ?? null;
  return displayName || avatarUrl ? { displayName: displayName ?? null, avatarUrl } : null;
}

function normalizeFeedItemType(value) {
  if (typeof value !== 'string') return null;
  const type = value
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_')
    .replace(/^music_/, '');
  return [
    'album',
    'artist',
    'channel',
    'category',
    'episode',
    'non_music_track',
    'playlist',
    'song',
    'subscriber',
    'video',
  ].includes(type)
    ? type
    : null;
}

function isTrackItemType(itemType) {
  return ['song', 'video', 'non_music_track'].includes(itemType);
}

function feedItemType(nodeType, payload = {}) {
  const browseId = typeof payload.browseId === 'string' ? payload.browseId : '';
  switch (nodeType) {
    case 'MusicNavigationButton':
      return 'category';
    case 'MusicMultiRowListItem':
      return 'episode';
  }
  if (browseId === 'FEmusic_moods_and_genres_category') return 'category';
  if (browseId.startsWith('VL')) return 'playlist';
  if (/^MPRE/i.test(browseId)) return 'album';
  if (browseId.startsWith('UC')) return 'artist';
  if (payload.videoId) return 'song';
  return 'unknown';
}

function normalizePlaylistId(value) {
  if (typeof value !== 'string') return '';
  return value.startsWith('VL') ? value.slice(2) : value;
}

function appendUniquePage(target, pageTracks, seenPages) {
  if (pageTracks.length === 0) return false;
  const fingerprint = pageTracks.map((track) => track.videoId).join('\u0000');
  if (seenPages.has(fingerprint)) return false;
  seenPages.add(fingerprint);
  target.push(...pageTracks);
  return true;
}

export class SidecarError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = 'SidecarError';
    this.code = code;
    this.details = details;
  }
}

export function serializeError(error) {
  return {
    code: error?.code ?? 'YOUTUBE_ERROR',
    message: error?.message ?? String(error),
    details: error?.details ?? null,
  };
}
