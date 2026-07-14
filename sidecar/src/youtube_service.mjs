import { Innertube, Platform, UniversalCache, YTNodes } from 'youtubei.js';
import { once } from 'node:events';
import { createWriteStream } from 'node:fs';
import { mkdir, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { finished } from 'node:stream/promises';

Platform.shim.eval = async (data) => Function(data.output)();

const MAX_LIBRARY_PAGES = 50;
const MAX_PLAYLIST_PAGES = 100;
const ACCOUNT_WRITE_COOLDOWN_MS = 2000;
const DOWNLOAD_CLIENTS = ['YTMUSIC', 'YTMUSIC_ANDROID', 'ANDROID', 'IOS'];

export class YouTubeService {
  constructor({
    createInnertube = createDefaultInnertube,
    emit = () => {},
    fetchImpl = globalThis.fetch,
    now = () => Date.now(),
  } = {}) {
    this.createInnertube = createInnertube;
    this.emit = emit;
    this.fetch = fetchImpl;
    this.now = now;
    this.locale = 'en';
    this.cookie = null;
    this.innertube = null;
    this.authMode = null;
    this.profile = null;
    this.homeFeed = null;
    this.exploreContinuation = null;
    this.nextAccountWriteAt = 0;
  }

  async restore(credential, locale) {
    this.locale = normalizeLocale(locale);
    if (!credential) {
      await this.#createSession();
      return { authenticated: false };
    }

    if (credential.kind !== 'cookie') {
      throw new SidecarError('INVALID_CREDENTIAL', 'Unsupported saved credential.');
    }
    return this.signInWithCookie(credential.value, this.locale);
  }

  async signInWithCookie(cookie, locale) {
    const value = typeof cookie === 'string' ? cookie.trim() : '';
    if (!value) {
      throw new SidecarError('INVALID_COOKIE', 'A YouTube Cookie header is required.');
    }

    this.locale = normalizeLocale(locale ?? this.locale);
    try {
      await this.#createSession(value);
      this.profile = mapAccountProfile(await this.innertube.account.getInfo());
      if (!this.profile) {
        throw new SidecarError(
          'INVALID_COOKIE',
          'The YouTube Cookie header is invalid or expired.',
        );
      }
      this.authMode = 'cookie';
      this.emit('auth.credentials', {
        credential: { kind: 'cookie', value },
      });
      return { authenticated: true, mode: this.authMode, profile: this.profile };
    } catch (error) {
      this.cookie = null;
      this.innertube = null;
      this.authMode = null;
      this.profile = null;
      if (error instanceof SidecarError) {
        throw error;
      }
      throw new SidecarError(
        'AUTHENTICATION_FAILED',
        'YouTube Cookie authentication failed.',
        describeUpstreamError(error),
      );
    }
  }

  async signOut() {
    this.cookie = null;
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

  async setLocale(locale) {
    const nextLocale = normalizeLocale(locale);
    if (nextLocale == this.locale) {
      return { locale: this.locale };
    }
    this.locale = nextLocale;
    await this.#createSession(this.cookie);
    return { locale: this.locale };
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

  async getHistory() {
    this.#requireAuthentication();

    const page = await this.innertube.actions.execute('/browse', {
      browseId: 'FEmusic_history',
      client: 'YTMUSIC',
      parse: true,
    });
    const tracks = [];
    const seen = new Set();
    for (const shelf of page.contents_memo?.getType(YTNodes.MusicShelf) ?? []) {
      for (const item of shelf.contents ?? []) {
        const track = mapTrack(item);
        if (track && !seen.has(track.videoId)) {
          tracks.push(track);
          seen.add(track.videoId);
        }
      }
    }
    return { tracks };
  }

  async getHomeFeed() {
    const feed = await this.innertube.music.getHomeFeed();
    this.homeFeed = feed;
    return {
      sections: mapFeedSections(feed.sections),
      hasMore: feed.has_continuation === true,
    };
  }

  async getMoreHomeFeed() {
    if (!this.homeFeed?.has_continuation) {
      return { sections: [], hasMore: false };
    }

    try {
      const feed = await this.homeFeed.getContinuation();
      this.homeFeed = feed;
      return {
        sections: mapFeedSections(feed.sections),
        hasMore: feed.has_continuation === true,
      };
    } catch (error) {
      if (/continuation did not have any content|continuation not found/i.test(
        error?.message ?? '',
      )) {
        this.homeFeed = null;
        return { sections: [], hasMore: false };
      }
      throw error;
    }
  }

  async getExploreFeed() {
    this.exploreContinuation = null;
    const feed = await this.innertube.music.getExplore();
    this.exploreContinuation = this.#exploreContinuationFor(feed);
    return {
      sections: mapFeedSections(feed.sections),
      hasMore: this.exploreContinuation !== null,
    };
  }

  async getMoreExploreFeed() {
    if (!this.exploreContinuation) {
      return { sections: [], hasMore: false };
    }

    try {
      const page = await this.innertube.actions.execute('/browse', {
        client: 'YTMUSIC',
        continuation: this.exploreContinuation,
        parse: true,
      });
      const continuation = page.continuation_contents?.as(
        YTNodes.SectionListContinuation,
      );
      this.exploreContinuation = continuation?.continuation ?? null;
      return {
        sections: mapFeedSections(
          continuation?.contents?.as(YTNodes.MusicCarouselShelf) ?? [],
        ),
        hasMore: this.exploreContinuation !== null,
      };
    } catch (error) {
      if (/continuation did not have any content|continuation not found/i.test(
        error?.message ?? '',
      )) {
        this.exploreContinuation = null;
        return { sections: [], hasMore: false };
      }
      throw error;
    }
  }

  async rateVideo(videoId, rating) {
    this.#requireAuthentication();
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to update its rating.',
      );
    }
    if (!['like', 'dislike', 'none'].includes(rating)) {
      throw new SidecarError('INVALID_RATING', 'Choose a valid rating.');
    }
    this.#beginAccountWrite();

    try {
      await this.#writeRating(videoId, rating);
      return { rating };
    } catch {
      throw new SidecarError(
        'RATING_UPDATE_FAILED',
        'Unable to update this track rating.',
      );
    }
  }

  async getComments(videoId) {
    this.#requireAuthentication();
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to load comments.',
      );
    }

    try {
      const comments = await this.innertube.getComments(videoId);
      return {
        comments: comments.contents.map(mapCommentThread).filter(Boolean),
        hasMore: comments.has_continuation === true,
      };
    } catch {
      throw new SidecarError(
        'COMMENTS_UNAVAILABLE',
        'Comments are unavailable for this track.',
      );
    }
  }

  async createComment(videoId, text) {
    this.#requireAuthentication();
    const comment = typeof text === 'string' ? text.trim() : '';
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to post a comment.',
      );
    }
    if (!comment) {
      throw new SidecarError('INVALID_COMMENT', 'Write a comment before posting.');
    }
    if (comment.length > 10000) {
      throw new SidecarError('INVALID_COMMENT', 'Comments can be up to 10,000 characters.');
    }
    this.#beginAccountWrite();

    try {
      await this.innertube.interact.comment(videoId, comment);
      return { posted: true };
    } catch {
      throw new SidecarError(
        'COMMENT_POST_FAILED',
        'Unable to post this comment.',
      );
    }
  }

  async searchMusic(query) {
    if (typeof query !== 'string' || !query.trim()) {
      return { items: [] };
    }
    const search = await this.innertube.music.search(query.trim());
    return { items: mapSearchItems(search.contents) };
  }

  async getLyrics(videoId, metadata = {}) {
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to load lyrics.',
      );
    }

    const timedLines = await getLrcLibLyrics(this.fetch, metadata);
    if (timedLines.length) {
      return { source: 'lrclib', lines: timedLines };
    }
    try {
      const officialLyrics = await this.innertube?.music?.getLyrics(videoId);
      const lines = plainLyricsLines(officialLyrics?.description);
      if (lines.length) {
        return { source: 'youtube_music', lines };
      }
    } catch {
      // Missing official lyrics is a normal empty state.
    }
    return { source: 'none', lines: [] };
  }

  async getFeedCollection(itemType, id) {
    this.#requireAuthentication();
    if (!['playlist', 'album'].includes(itemType) || !id) {
      throw new SidecarError(
        'INVALID_FEED_ITEM',
        'Only playlist and album feed items can be loaded as a collection.',
      );
    }

    if (itemType === 'album') {
      let album;
      try {
        album = await this.innertube.music.getAlbum(id);
      } catch (error) {
        throw feedFailure(
          'COLLECTION_REQUEST_FAILED',
          'Unable to load this collection.',
          'collection.album.request',
          error,
        );
      }
      try {
        return { tracks: listOf(album?.contents).map(mapTrack).filter(Boolean) };
      } catch (error) {
        throw feedFailure(
          'COLLECTION_PARSE_FAILED',
          'Unable to read this collection.',
          'collection.album.parse',
          error,
        );
      }
    }

    let page;
    try {
      page = await this.innertube.music.getPlaylist(id);
    } catch (error) {
      throw feedFailure(
        'COLLECTION_REQUEST_FAILED',
        'Unable to load this collection.',
        'collection.playlist.request',
        error,
      );
    }
    const tracks = [];
    const seenPages = new Set();
    try {
      for (let index = 0; index < MAX_PLAYLIST_PAGES && page; index += 1) {
        const pageTracks = listOf(page.items).map(mapTrack).filter(Boolean);
        if (!appendUniquePage(tracks, pageTracks, seenPages)) break;
        page = page.has_continuation && typeof page.getContinuation === 'function'
          ? await page.getContinuation()
          : null;
      }
    } catch (error) {
      throw feedFailure(
        'COLLECTION_PARSE_FAILED',
        'Unable to read this collection.',
        'collection.playlist.parse',
        error,
      );
    }
    return { tracks };
  }

  async getFeedTrack(videoId) {
    this.#requireAuthentication();
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
        thumbnailUrl: largestArtworkThumbnail(arrayOf(basicInfo?.thumbnail))?.url ?? null,
      },
    };
  }

  async getPlaybackStream(videoId) {
    this.#requireAuthentication();
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to start playback.',
      );
    }

    try {
      const format = await this.innertube.getStreamingData(videoId, {
        client: 'YTMUSIC',
        type: 'audio',
        quality: 'best',
        format: 'any',
      });
      if (!format?.url || !format.mime_type) {
        throw new SidecarError(
          'PLAYBACK_UNAVAILABLE',
          'YouTube did not provide an audio stream for this track.',
        );
      }
      return {
        stream: {
          url: format.url,
          mimeType: format.mime_type,
          bitrate: format.bitrate,
          durationSeconds: Math.round((format.approx_duration_ms ?? 0) / 1000),
        },
      };
    } catch (error) {
      if (error instanceof SidecarError) {
        throw error;
      }
      if (/unplayable|login required/i.test(error?.message ?? '')) {
        throw new SidecarError(
          'PLAYBACK_UNAVAILABLE',
          'This track is unavailable for playback.',
          describeUpstreamError(error),
        );
      }
      throw new SidecarError(
        'PLAYBACK_RESOLUTION_FAILED',
        'Unable to prepare this track for playback.',
        describeUpstreamError(error),
      );
    }
  }

  async downloadAudio(videoId, directory) {
    this.#requireAuthentication();
    if (!/^[A-Za-z0-9_-]+$/.test(videoId ?? '')) {
      throw new SidecarError('INVALID_VIDEO_ID', 'A valid video ID is required to download audio.');
    }
    if (typeof directory !== 'string' || directory.trim().length === 0) {
      throw new SidecarError('INVALID_DOWNLOAD_DIRECTORY', 'A download directory is required.');
    }

    const baseDownloadOptions = {
      type: 'audio',
      quality: 'best',
      format: 'any',
    };
    let writer;
    let temporaryPath;
    let diagnosticStage = 'download.session';
    try {
      // Reuse the authenticated session and its loaded player. Creating a
      // second Innertube instance can hang while retrieving the player script,
      // before any download metadata request is made.
      const downloadInnertube = this.innertube;
      let info;
      let format;
      let downloadOptions;
      let lastFailure;
      let metadataSucceeded = false;
      for (const client of DOWNLOAD_CLIENTS) {
        const candidateOptions = { ...baseDownloadOptions, client };
        diagnosticStage = 'download.metadata';
        let candidateInfo;
        try {
          candidateInfo = await downloadInnertube.getBasicInfo(videoId, candidateOptions);
          metadataSucceeded = true;
        } catch (error) {
          lastFailure = error;
          continue;
        }
        diagnosticStage = 'download.format';
        try {
          const candidateFormat = candidateInfo.chooseFormat(candidateOptions);
          if (candidateFormat?.mime_type) {
            info = candidateInfo;
            format = candidateFormat;
            downloadOptions = candidateOptions;
            break;
          }
        } catch (error) {
          lastFailure = error;
        }
      }
      if (!info || !format || !downloadOptions) {
        if (!metadataSucceeded && lastFailure) {
          diagnosticStage = 'download.metadata';
          throw lastFailure;
        }
        diagnosticStage = 'download.format';
        throw new SidecarError(
          'DOWNLOAD_UNAVAILABLE',
          'YouTube did not provide an audio stream for this track.',
          {
            diagnosticStage,
            ...describeUpstreamError(lastFailure),
          },
        );
      }
      const outputPath = path.resolve(
        directory,
        `${videoId}.${audioExtension(format.mime_type)}`,
      );
      temporaryPath = `${outputPath}.part`;
      await mkdir(path.dirname(outputPath), { recursive: true });
      diagnosticStage = 'download.stream';
      const audioStream = await info.download(downloadOptions);
      const totalBytes = null;
      let receivedBytes = 0;
      writer = createWriteStream(temporaryPath);
      diagnosticStage = 'download.write';
      for await (const chunk of Readable.fromWeb(audioStream)) {
        receivedBytes += chunk.length;
        if (!writer.write(chunk)) {
          await once(writer, 'drain');
        }
        this.emit('download.progress', { videoId, receivedBytes, totalBytes });
      }
      writer.end();
      await finished(writer);
      if (totalBytes !== null && receivedBytes !== totalBytes) {
        throw new Error('The audio stream ended before the download completed.');
      }
      await rm(outputPath, { force: true });
      await rename(temporaryPath, outputPath);
      return { path: outputPath, mimeType: format.mime_type };
    } catch (error) {
      writer?.destroy();
      if (temporaryPath) {
        await rm(temporaryPath, { force: true });
      }
      if (error instanceof SidecarError) {
        throw error;
      }
      throw new SidecarError(
        error?.name === 'TimeoutError' ? 'DOWNLOAD_TIMED_OUT' : 'DOWNLOAD_FAILED',
        error?.name === 'TimeoutError'
          ? 'The audio download timed out.'
          : 'Unable to download this track.',
        {
          diagnosticStage,
          ...describeUpstreamError(error),
        },
      );
    }
  }

  async getFeedBrowse(itemType, id, params) {
    this.#requireAuthentication();
    if (!['artist', 'category', 'channel', 'subscriber'].includes(itemType) || !id) {
      throw new SidecarError(
        'INVALID_FEED_ITEM',
        'Only artist, channel, or category feed items can be opened as browse pages.',
      );
    }

    let page;
    try {
      page = await this.innertube.actions.execute('browse', {
        browseId: id,
        ...(params ? { params } : {}),
        client: 'YTMUSIC',
        parse: true,
      });
    } catch (error) {
      throw feedFailure(
        'BROWSE_REQUEST_FAILED',
        'Unable to load this page.',
        'browse.request',
        error,
      );
    }
    try {
      return { sections: mapBrowseFeedSections(page) };
    } catch (error) {
      throw feedFailure(
        'BROWSE_PARSE_FAILED',
        'Unable to read this page.',
        'browse.parse',
        error,
      );
    }
  }

  async #createSession(cookie) {
    this.cookie = cookie ?? null;
    this.innertube = await this.createInnertube(this.cookie, this.locale);
    this.authMode = this.cookie ? 'cookie' : null;
    this.homeFeed = null;
    this.exploreContinuation = null;
    this.nextAccountWriteAt = 0;
  }

  #exploreContinuationFor(feed) {
    const tab = feed.page?.contents
        ?.item()
        ?.as(YTNodes.SingleColumnBrowseResults)
        .tabs.find((entry) => entry.selected);
    return tab?.content?.as(YTNodes.SectionList).continuation ?? null;
  }

  #requireAuthentication() {
    if (this.authMode !== 'cookie') {
      throw new SidecarError('AUTH_REQUIRED', 'Sign in before loading your library.');
    }
  }

  #beginAccountWrite() {
    const now = this.now();
    if (now < this.nextAccountWriteAt) {
      throw new SidecarError(
        'ACCOUNT_WRITE_THROTTLED',
        'Wait a moment before another YouTube action.',
      );
    }
    this.nextAccountWriteAt = now + ACCOUNT_WRITE_COOLDOWN_MS;
  }

  async #writeRating(videoId, rating) {
    switch (rating) {
      case 'like':
        return this.innertube.interact.like(videoId);
      case 'dislike':
        return this.innertube.interact.dislike(videoId);
      case 'none':
        return this.innertube.interact.removeRating(videoId);
    }
  }
}

async function createDefaultInnertube(cookie, locale) {
  return Innertube.create({
    cookie,
    cache: new UniversalCache(false),
    lang: normalizeLocale(locale),
    device_category: 'DESKTOP',
    generate_session_locally: true,
    retrieve_player: true,
    retrieve_innertube_config: false,
  });
}

function normalizeLocale(locale) {
  return typeof locale === 'string' && locale.toLowerCase().startsWith('zh')
    ? 'zh-CN'
    : 'en';
}

export function mapPlaylist(item) {
  const type = item?.type ?? item?.constructor?.type ?? item?.constructor?.name;
  const rawItemType = item?.item_type ?? item?.content_type;
  const itemType = typeof rawItemType === 'string'
    ? rawItemType.toLowerCase()
    : null;
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
    thumbnailUrl: largestArtworkThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

export function mapTrack(item) {
  const type = item?.type ?? item?.constructor?.type ?? item?.constructor?.name;
  const rawItemType = item?.item_type ?? item?.content_type;
  const itemType = typeof rawItemType === 'string'
    ? rawItemType.toLowerCase()
    : null;
  if (
    !item ||
    !['song', 'video', 'non_music_track'].includes(itemType) &&
      !['PlaylistVideo', 'LockupView', 'Video'].includes(type)
  ) {
    return null;
  }
  const videoId = item.id ?? item.content_id ?? item.endpoint?.payload?.videoId;
  const title = textValue(item.title ?? item.metadata?.title);
  if (!videoId || !title) return null;

  const subtitle = textValue(item.subtitle ?? item.second_title ?? item.description);
  const artists = listOf(
    item.artists ?? item.authors ?? (item.author ? [item.author] : []),
  );
  const artistNames = artists
    .map((artist) => textValue(artist?.name ?? artist))
    .filter(Boolean);
  return {
    videoId,
    title,
    artists: artistNames.length ? artistNames : artistsFromSubtitle(subtitle),
    album: textValue(item.album?.name ?? item.album) ?? albumFromSubtitle(subtitle),
    durationSeconds: item.duration?.seconds ?? 0,
    thumbnailUrl: largestArtworkThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

export function mapCommentThread(thread) {
  const comment = thread?.comment;
  const id = comment?.comment_id;
  const text = textValue(comment?.content);
  if (!id || !text) return null;

  return {
    id,
    author: textValue(comment?.author?.name) || 'YouTube listener',
    text,
    publishedTime: textValue(comment?.published_time),
    avatarUrl: largestArtworkThumbnail(comment?.author?.thumbnails ?? [])?.url ?? null,
    likeCount: textValue(comment?.like_count),
  };
}

export function mapFeedSections(rawSections) {
  return listOf(rawSections)
    .map((section, sectionIndex) => {
      const title = textValue(section?.header?.title);
      const items = listOf(section?.contents)
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
  const contents = page?.contents;
  const root = typeof contents?.item === 'function' ? contents.item() : contents;
  const tabs = listOf(root?.tabs);
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

  const artists = listOf(
    item?.artists ?? item?.authors ?? (item?.author ? [item.author] : []),
  );
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
    thumbnailUrl: largestArtworkThumbnail(thumbnailCandidates(item))?.url ?? null,
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
    thumbnailUrl: largestArtworkThumbnail([
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

function listOf(value) {
  if (!value) return [];
  if (typeof value === 'string') return [value];
  if (Array.isArray(value)) return value;
  if (typeof value[Symbol.iterator] === 'function') return [...value];
  return [value];
}

function largestThumbnail(thumbnails) {
  return thumbnails
    .filter((thumbnail) => thumbnail?.url)
    .sort((a, b) => (b.width ?? 0) - (a.width ?? 0))[0];
}

function largestArtworkThumbnail(thumbnails) {
  const thumbnail = largestThumbnail(thumbnails);
  if (!thumbnail) return null;
  return {
    ...thumbnail,
    url: highResolutionArtworkUrl(thumbnail.url),
  };
}

function highResolutionArtworkUrl(url) {
  if (!url.includes('googleusercontent.com')) return url;
  return url.replace(/=[^?]+$/, '=w1200-h1200-l90-rj');
}

function audioExtension(mimeType) {
  if (mimeType.startsWith('audio/mp4')) return 'm4a';
  if (mimeType.startsWith('audio/webm')) return 'webm';
  return 'audio';
}

async function getLrcLibLyrics(fetchImpl, metadata) {
  const { title, artist, album, durationSeconds } = metadata;
  if (
    typeof fetchImpl !== 'function' ||
    ![title, artist].every((value) => typeof value === 'string' && value.trim())
  ) {
    return [];
  }

  const hasExactMetadata =
    typeof album === 'string' &&
    album.trim() &&
    Number.isInteger(durationSeconds) &&
    durationSeconds > 0;
  try {
    const cachedLookup = hasExactMetadata
      ? getExactLrcLibLyrics(
        fetchImpl,
        'get-cached',
        title,
        artist,
        album,
        durationSeconds,
        3000,
      )
      : Promise.resolve([]);

    const searchLookup = (async () => {
      const search = new URL('https://lrclib.net/api/search');
      search.searchParams.set('track_name', title);
      search.searchParams.set('artist_name', artist);
      const response = await fetchLrcLib(fetchImpl, search);
      if (!response.ok) return [];
      const records = await response.json();
      if (!Array.isArray(records)) return [];
      for (const record of records) {
        const lines = timedLyricsLines(record?.syncedLyrics);
        if (lines.length) return lines;
      }
      return [];
    })();

    const [cachedResult, searchResult] = await Promise.allSettled([
      cachedLookup,
      searchLookup,
    ]);
    const cachedLines =
      cachedResult.status === 'fulfilled' ? cachedResult.value : [];
    const searchLines =
      searchResult.status === 'fulfilled' ? searchResult.value : [];
    if (cachedLines.length || searchLines.length || !hasExactMetadata) {
      return cachedLines.length ? cachedLines : searchLines;
    }
    return await getExactLrcLibLyrics(
      fetchImpl,
      'get',
      title,
      artist,
      album,
      durationSeconds,
      8000,
    ).catch(() => []);
  } catch {
    return [];
  }
}

async function getExactLrcLibLyrics(
  fetchImpl,
  endpoint,
  title,
  artist,
  album,
  durationSeconds,
  timeoutMs,
) {
  const url = new URL(`https://lrclib.net/api/${endpoint}`);
  url.searchParams.set('track_name', title);
  url.searchParams.set('artist_name', artist);
  url.searchParams.set('album_name', album);
  url.searchParams.set('duration', String(durationSeconds));
  const response = await fetchLrcLib(fetchImpl, url, timeoutMs);
  if (!response.ok) return [];
  return timedLyricsLines((await response.json())?.syncedLyrics);
}

function fetchLrcLib(fetchImpl, url, timeoutMs = 3000) {
  return fetchImpl(url, {
    headers: { 'User-Agent': 'Otoha/0.1 (desktop music player)' },
    signal: AbortSignal.timeout(timeoutMs),
  });
}

function timedLyricsLines(value) {
  if (typeof value !== 'string') return [];
  const lines = [];
  const timestamp = /\[(\d+):(\d{2}(?:\.\d{1,3})?)\]/g;
  for (const rawLine of value.split(/\r?\n/)) {
    const timestamps = [...rawLine.matchAll(timestamp)];
    const text = rawLine.replace(timestamp, '').trim();
    if (!text || !timestamps.length) continue;
    for (const match of timestamps) {
      lines.push({
        text,
        startSeconds: Number(match[1]) * 60 + Number(match[2]),
      });
    }
  }
  return lines.sort((left, right) => left.startSeconds - right.startSeconds);
}

function plainLyricsLines(value) {
  const lyrics = textValue(value);
  if (!lyrics) return [];
  return lyrics
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((text) => ({ text, startSeconds: null }));
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

function feedFailure(code, message, diagnosticStage, error) {
  return new SidecarError(code, message, {
    diagnosticStage,
    ...describeUpstreamError(error),
  });
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
  const isSidecarError = error instanceof SidecarError;
  return {
    code: isSidecarError ? error.code : 'YOUTUBE_ERROR',
    message: isSidecarError
      ? error.message
      : 'The YouTube service could not complete this request.',
    details: describeUpstreamError(error),
  };
}

export function describeUpstreamError(error) {
  const details = error?.details;
  const isSidecarError = error instanceof SidecarError;
  const diagnosticStage = safeDiagnosticValue(details?.diagnosticStage);
  const statusCode = firstStatusCode(
    details?.statusCode,
    error?.status_code,
    error?.statusCode,
    error?.response?.status,
  );
  const upstreamCode =
    safeDiagnosticValue(details?.upstreamCode) ??
    (isSidecarError ? null : safeDiagnosticValue(error?.code));
  const sourceLocation =
    safeSourceLocation(details?.sourceLocation) ?? safeStackLocation(error?.stack);
  const errorType =
    safeDiagnosticValue(details?.errorType) ??
    safeDiagnosticValue(error?.name) ??
    'Error';
  return {
    errorType,
    ...(diagnosticStage == null ? {} : { diagnosticStage }),
    ...(statusCode == null ? {} : { statusCode }),
    ...(sourceLocation == null ? {} : { sourceLocation }),
    ...(upstreamCode == null ? {} : { upstreamCode }),
  };
}

function firstStatusCode(...candidates) {
  for (const candidate of candidates) {
    if (Number.isInteger(candidate) && candidate >= 100 && candidate <= 599) {
      return candidate;
    }
  }
  return null;
}

function safeDiagnosticValue(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_.-]{1,80}$/.test(value)) {
    return null;
  }
  return value;
}

function safeSourceLocation(value) {
  if (
    typeof value !== 'string' ||
    !/^sidecar\/src\/[A-Za-z0-9_.-]+\.mjs:\d+:\d+$/.test(value)
  ) {
    return null;
  }
  return value;
}

function safeStackLocation(stack) {
  if (typeof stack !== 'string') return null;
  const match = stack.match(
    /(?:file:\/\/)?(?:[^\s()]*\/)?(sidecar\/src\/[A-Za-z0-9_.-]+\.mjs:\d+:\d+)/,
  );
  return safeSourceLocation(match?.[1]);
}
