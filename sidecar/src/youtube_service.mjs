import {
  Innertube,
  MusicShelfContinuation,
  Parser,
  Platform,
  SectionListContinuation,
  UniversalCache,
  YTNodes,
  YTMusic,
} from 'youtubei.js';
import { once } from 'node:events';
import { createWriteStream } from 'node:fs';
import { mkdir, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { finished } from 'node:stream/promises';

Platform.shim.eval = async (data) => Function(data.output)();

const MAX_LIBRARY_PAGES = 50;
const MAX_PLAYLIST_PAGES = 100;
const ACCOUNT_WRITE_COOLDOWN_MS = 2000;
const DOWNLOAD_CLIENTS = ['YTMUSIC', 'YTMUSIC_ANDROID', 'ANDROID', 'IOS'];
const ARTIST_SUBSCRIBE_PARAMS = 'EgIIAhgA';
const ARTIST_UNSUBSCRIBE_PARAMS = 'CgIIAhgA';
const SAVED_EPISODES_PLAYLIST_ID = 'SE';
const MUSIC_SEARCH_FILTERS = new Set([
  'all',
  'song',
  'album',
  'artist',
  'playlist',
  'video',
]);

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
    this.homeRootFeed = null;
    this.homeFilters = [];
    this.exploreContinuation = null;
    this.podcastBrowseId = null;
    this.podcastBrowseContinuation = null;
    this.playlistPages = new Map();
    this.specialCollectionPages = new Map();
    this.historyContinuation = null;
    this.historySeenVideoIds = new Set();
    this.artistSubscriptionButtons = new Map();
    this.albumLibraryTargets = new Map();
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
    const value = normalizeCookieHeader(cookie);
    if (!value) {
      throw new SidecarError('INVALID_COOKIE', 'A YouTube Cookie header is required.');
    }

    this.locale = normalizeLocale(locale ?? this.locale);
    let diagnosticStage = 'auth.session';
    try {
      await this.#createSession(value);
      diagnosticStage = 'auth.profile';
      try {
        // Cookie authentication belongs to the web client. The default
        // AccountManager probe uses TV and can reject an otherwise valid
        // YouTube Music session.
        this.profile = mapAccountProfile(
          await this.innertube.account.getInfo(true),
        );
      } catch {
        this.profile = null;
      }

      if (!this.profile) {
        diagnosticStage = 'auth.library';
        try {
          // Profile metadata is optional. Validate the capability Otoha
          // actually needs before rejecting the Cookie.
          await this.innertube.music.getLibrary();
        } catch (error) {
          throw authenticationFailure(error, diagnosticStage);
        }
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
      throw authenticationFailure(error, diagnosticStage);
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

  async getLibraryMedia() {
    this.#requireAuthentication();

    let library;
    try {
      library = await this.innertube.music.getLibrary();
    } catch (error) {
      throw feedFailure(
        'LIBRARY_LOAD_FAILED',
        'Unable to load your YouTube media library.',
        'library.root',
        error,
      );
    }
    const [playlists, followedArtists, podcasts, albums, savedCollections] =
      await Promise.all([
        this.#loadLibrarySection(
          library,
          'playlists',
          (page) =>
            this.#collectLibraryItems(page, mapPlaylist, (item) => item.id),
          { required: true },
        ),
        this.#loadLibrarySection(
          library,
          'artists',
          (page) =>
            this.#collectLibraryItems(
              page,
              mapFollowedArtist,
              (item) => item.id,
            ),
        ),
        this.#loadLibrarySection(
          library,
          'podcasts',
          (page) => this.#collectPodcastLibraryShows(page),
        ),
        this.#loadLibrarySection(
          library,
          'albums',
          (page) =>
            this.#collectLibraryItems(page, mapLibraryAlbum, (item) => item.id),
        ),
        this.#getSpecialCollectionSummaries(),
      ]);
    return {
      playlists,
      followedArtists,
      savedCollections,
      podcasts,
      albums,
    };
  }

  async getPlaylist(playlistId) {
    this.#requireAuthentication();
    const id = normalizePlaylistId(playlistId);
    if (!id) {
      throw new SidecarError('INVALID_PLAYLIST_ID', 'A playlist ID is required.');
    }

    let page = await this.innertube.music.getPlaylist(id);
    const playlist = mapPlaylistHeader(id, page.header, page.background);
    return this.#startPlaylistPage(id, playlist, page, this.playlistPages);
  }

  async getMorePlaylist(playlistId) {
    this.#requireAuthentication();
    const id = normalizePlaylistId(playlistId);
    if (!id) {
      throw new SidecarError('INVALID_PLAYLIST_ID', 'A playlist ID is required.');
    }
    return this.#getMorePlaylistPage(id, this.playlistPages);
  }

  async getSpecialCollection(kind) {
    this.#requireAuthentication();
    const collection = normalizeSpecialCollectionKind(kind);
    if (!collection) {
      throw new SidecarError(
        'INVALID_LIBRARY_COLLECTION',
        'Choose a valid saved library collection.',
      );
    }

    const library = await this.innertube.getLibrary();
    const section = library.liked_videos;
    if (!section) {
      throw new SidecarError(
        'LIBRARY_COLLECTION_UNAVAILABLE',
        'This saved collection is unavailable for the current account.',
      );
    }
    const page = await section.getAll();
    return this.#startPlaylistPage(
      collection,
      mapSpecialLibraryCollection(collection, section),
      page,
      this.specialCollectionPages,
    );
  }

  async getMoreSpecialCollection(kind) {
    this.#requireAuthentication();
    const collection = normalizeSpecialCollectionKind(kind);
    if (!collection) {
      throw new SidecarError(
        'INVALID_LIBRARY_COLLECTION',
        'Choose a valid saved library collection.',
      );
    }
    return this.#getMorePlaylistPage(collection, this.specialCollectionPages);
  }

  async getHistory() {
    this.#requireAuthentication();

    const page = await this.innertube.actions.execute('/browse', {
      browseId: 'FEmusic_history',
      client: 'YTMUSIC',
      parse: true,
    });
    const history = mapHistoryPage(page);
    this.historySeenVideoIds = new Set();
    const tracks = [];
    appendUniqueTracks(tracks, history.tracks, this.historySeenVideoIds);
    this.historyContinuation = history.continuation;
    return { tracks, hasMore: this.historyContinuation !== null };
  }

  async getMoreHistory() {
    this.#requireAuthentication();
    if (!this.historyContinuation) {
      return { tracks: [], hasMore: false };
    }

    try {
      const page = await this.innertube.actions.execute('/browse', {
        client: 'YTMUSIC',
        continuation: this.historyContinuation,
      });
      const history = mapHistoryPage(page);
      const tracks = [];
      const appended = appendUniqueTracks(
        tracks,
        history.tracks,
        this.historySeenVideoIds,
      );
      this.historyContinuation = appended ? history.continuation : null;
      return {
        tracks,
        hasMore: this.historyContinuation !== null,
      };
    } catch (error) {
      if (isContinuationExhausted(error)) {
        this.historyContinuation = null;
        return { tracks: [], hasMore: false };
      }
      throw error;
    }
  }

  async getHomeFeed() {
    const feed = await this.innertube.music.getHomeFeed();
    this.homeFeed = feed;
    this.homeRootFeed = feed;
    this.homeFilters = listOf(feed.filters).map(textValue).filter(Boolean);
    return {
      sections: mapFeedSections(feed.sections),
      filters: this.homeFilters,
      selectedFilter: null,
      hasMore: feed.has_continuation === true,
    };
  }

  async applyHomeFilter(filter) {
    const value = typeof filter === 'string' ? filter.trim() : '';
    if (!value) {
      throw new SidecarError(
        'INVALID_HOME_FILTER',
        'Choose a valid Home filter.',
      );
    }
    if (!this.homeRootFeed) {
      await this.getHomeFeed();
    }
    if (!this.homeFilters.includes(value)) {
      throw new SidecarError(
        'INVALID_HOME_FILTER',
        'Choose a valid Home filter.',
      );
    }

    let feed;
    try {
      feed = await this.homeRootFeed.applyFilter(value);
    } catch (error) {
      throw feedFailure(
        'HOME_FILTER_FAILED',
        'Unable to load this Home filter.',
        'home.filter',
        error,
      );
    }
    this.homeFeed = feed;
    return {
      sections: mapFeedSections(feed.sections),
      filters: this.homeFilters,
      selectedFilter: value,
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
    const response = await this.innertube.actions.execute('/browse', {
      client: 'YTMUSIC',
      browseId: 'FEmusic_explore',
    });
    const feed = new YTMusic.Explore(response);
    this.exploreContinuation = this.#exploreContinuationFor(feed);
    return {
      sections: mapExploreFeedSections(feed, this.locale, response.data),
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
        SectionListContinuation,
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
    } catch (error) {
      throw feedFailure(
        'RATING_UPDATE_FAILED',
        'Unable to update this track rating.',
        'rating.update',
        error,
      );
    }
  }

  async setSubscription(channelId, subscribed) {
    this.#requireAuthentication();
    if (!channelId) {
      throw new SidecarError(
        'INVALID_CHANNEL_ID',
        'A channel ID is required to update a subscription.',
      );
    }
    if (typeof subscribed !== 'boolean') {
      throw new SidecarError(
        'INVALID_SUBSCRIPTION_STATE',
        'Choose whether to follow this artist.',
      );
    }
    this.#beginAccountWrite();
    try {
      const update = await this.#writeSubscription(channelId, subscribed);
      return update;
    } catch (error) {
      throw feedFailure(
        'SUBSCRIPTION_UPDATE_FAILED',
        'Unable to update this artist subscription.',
        'subscription.update',
        error,
      );
    }
  }

  async setEpisodeForLater(videoId, saved) {
    this.#requireAuthentication();
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A podcast episode video ID is required.',
      );
    }
    if (typeof saved !== 'boolean') {
      throw new SidecarError(
        'INVALID_SAVED_EPISODE_STATE',
        'Choose whether to save this podcast episode for later.',
      );
    }
    this.#beginAccountWrite();
    try {
      if (saved) {
        await this.innertube.playlist.addVideos(
          SAVED_EPISODES_PLAYLIST_ID,
          [videoId],
        );
      } else {
        const response = await this.innertube.actions.execute(
          'browse/edit_playlist',
          {
            playlistId: SAVED_EPISODES_PLAYLIST_ID,
            actions: [
              {
                action: 'ACTION_REMOVE_VIDEO_BY_VIDEO_ID',
                removedVideoId: videoId,
              },
            ],
            client: 'YTMUSIC',
          },
        );
        if (response?.success === false) {
          throw httpResponseError(
            response.status_code,
            'YouTube saved episode update',
          );
        }
      }
      this.playlistPages.delete(SAVED_EPISODES_PLAYLIST_ID);
      return { saved };
    } catch (error) {
      throw feedFailure(
        'SAVED_EPISODE_UPDATE_FAILED',
        'Unable to update this saved podcast episode.',
        'saved_episode.update',
        error,
      );
    }
  }

  async setPodcastInLibrary(podcastId, saved) {
    this.#requireAuthentication();
    if (!podcastId) {
      throw new SidecarError(
        'INVALID_PODCAST_ID',
        'A podcast show ID is required.',
      );
    }
    if (typeof saved !== 'boolean') {
      throw new SidecarError(
        'INVALID_PODCAST_LIBRARY_STATE',
        'Choose whether to save this podcast show to the media library.',
      );
    }
    this.#beginAccountWrite();
    try {
      await this.#setPodcastLibraryState(
        normalizePlaylistId(podcastId),
        saved,
      );
      return { saved };
    } catch (error) {
      throw feedFailure(
        'PODCAST_LIBRARY_UPDATE_FAILED',
        'Unable to update this podcast show in the media library.',
        'podcast.library.update',
        error,
      );
    }
  }

  async #setPodcastLibraryState(podcastId, saved) {
    try {
      const response = saved
        ? await this.innertube.playlist.addToLibrary(podcastId)
        : await this.innertube.playlist.removeFromLibrary(podcastId);
      if (response?.success !== false) return response;
      if (response.status_code !== 400) {
        throw httpResponseError(
          response.status_code,
          'YouTube podcast library update',
        );
      }
    } catch (error) {
      if (describeUpstreamError(error).statusCode !== 400) throw error;
    }

    // youtubei.js 17.2.0 serializes likeEndpoint.target as a string, while
    // YouTube Music expects target.playlistId for podcast playlists.
    const response = await this.innertube.actions.execute(
      saved ? 'like/like' : 'like/removelike',
      {
        target: { playlistId: podcastId },
        client: 'YTMUSIC',
      },
    );
    if (response?.success === false) {
      throw httpResponseError(
        response.status_code,
        'YouTube podcast library update',
      );
    }
    return response;
  }

  async setAlbumInLibrary(albumId, saved) {
    this.#requireAuthentication();
    const id = typeof albumId === 'string' ? albumId.trim() : '';
    if (!id) {
      throw new SidecarError(
        'INVALID_ALBUM_ID',
        'An album browse ID is required.',
      );
    }
    if (typeof saved !== 'boolean') {
      throw new SidecarError(
        'INVALID_ALBUM_LIBRARY_STATE',
        'Choose whether to save this album to the media library.',
      );
    }
    this.#beginAccountWrite();

    try {
      let playlistId = this.albumLibraryTargets.get(id);
      if (!playlistId) {
        const album = await this.innertube.music.getAlbum(id);
        playlistId = albumAudioPlaylistId(album);
        if (playlistId) {
          this.albumLibraryTargets.set(id, playlistId);
        }
      }
      if (!playlistId) {
        throw new SidecarError(
          'ALBUM_LIBRARY_TARGET_UNAVAILABLE',
          'This album does not expose a media-library action.',
        );
      }

      const response = await this.innertube.actions.execute(
        saved ? 'like/like' : 'like/removelike',
        {
          target: { playlistId },
          client: 'YTMUSIC',
        },
      );
      if (response?.success === false) {
        throw httpResponseError(
          response.status_code,
          'YouTube album library update',
        );
      }
      return { albumId: id, saved };
    } catch (error) {
      if (error?.code === 'ALBUM_LIBRARY_TARGET_UNAVAILABLE') {
        throw error;
      }
      throw feedFailure(
        'ALBUM_LIBRARY_UPDATE_FAILED',
        'Unable to update this album in the media library.',
        'album.library.update',
        error,
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
        commentsAvailable: true,
      };
    } catch (error) {
      const details = describeUpstreamError(error);
      if (isNetworkFailure(error, details.upstreamCode)) {
        throw new SidecarError(
          'COMMENTS_LOAD_FAILED',
          'Unable to reach YouTube comments for this track.',
          { diagnosticStage: 'comments.load', ...details },
        );
      }
      // Music tracks commonly disable public comments. Treat that as empty
      // content rather than a failed player action.
      return { comments: [], hasMore: false, commentsAvailable: false };
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

  async searchMusic(query, filter = 'all') {
    const normalizedFilter = typeof filter === 'string' ? filter.trim() : '';
    if (!MUSIC_SEARCH_FILTERS.has(normalizedFilter)) {
      throw new SidecarError(
        'INVALID_SEARCH_FILTER',
        'Choose a valid YouTube Music search filter.',
      );
    }
    if (typeof query !== 'string' || !query.trim()) {
      return { items: [] };
    }
    const search = await this.innertube.music.search(query.trim(), {
      type: normalizedFilter,
    });
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
        const playlistId = albumAudioPlaylistId(album);
        if (playlistId) {
          this.albumLibraryTargets.set(id, playlistId);
        }
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

    let lastFailure;
    for (const client of DOWNLOAD_CLIENTS) {
      try {
        const info = await this.innertube.getBasicInfo(videoId, { client });
        const basicInfo = info?.basic_info;
        const title = textValue(basicInfo?.title);
        if (!title) {
          lastFailure = new Error('Track metadata was empty');
          continue;
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
            thumbnailUrl:
              largestArtworkThumbnail(arrayOf(basicInfo?.thumbnail))?.url ??
              null,
          },
        };
      } catch (error) {
        lastFailure = error;
      }
    }
    throw new SidecarError(
      'TRACK_METADATA_UNAVAILABLE',
      'YouTube did not return track metadata for this item.',
      describeUpstreamError(lastFailure),
    );
  }

  async getPlaybackStream(videoId, mediaType = 'audio') {
    this.#requireAuthentication();
    if (!videoId) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A video ID is required to start playback.',
      );
    }
    if (!['audio', 'video'].includes(mediaType)) {
      throw new SidecarError(
        'INVALID_MEDIA_TYPE',
        'Playback media type must be audio or video.',
      );
    }

    let lastFailure;
    if (mediaType === 'video') {
      for (const client of DOWNLOAD_CLIENTS) {
        try {
          const info = await this.innertube.getBasicInfo(videoId, { client });
          const hlsUrl = info?.streaming_data?.hls_manifest_url;
          if (info?.basic_info?.is_live && typeof hlsUrl === 'string') {
            return {
              stream: {
                url: hlsUrl,
                mimeType: 'application/x-mpegURL',
                durationSeconds: 0,
                mediaType,
              },
            };
          }
          const formats = selectAdaptivePlaybackFormats(info);
          if (!formats) {
            lastFailure = new Error('Adaptive audio or video was unavailable');
            continue;
          }
          const [videoUrl, audioUrl] = await Promise.all([
            formats.video.decipher(this.innertube.session?.player),
            formats.audio.decipher(this.innertube.session?.player),
          ]);
          if (!videoUrl || !audioUrl) {
            lastFailure = new Error('Adaptive stream URL was empty');
            continue;
          }
          return {
            stream: {
              url: videoUrl,
              audioUrl,
              mimeType: formats.video.mime_type,
              audioMimeType: formats.audio.mime_type,
              width: Number(formats.video.width ?? 0),
              height: Number(formats.video.height ?? 0),
              durationSeconds: Number.isInteger(info?.basic_info?.duration)
                ? info.basic_info.duration
                : 0,
              mediaType,
            },
          };
        } catch (error) {
          lastFailure = error;
        }
      }
    } else {
      for (const client of DOWNLOAD_CLIENTS) {
        try {
          const format = await this.innertube.getStreamingData(videoId, {
            client,
            type: 'audio',
            quality: 'best',
            format: 'any',
          });
          if (!format?.url || !format.mime_type) {
            lastFailure = new Error('No matching formats found');
            continue;
          }
          return {
            stream: {
              url: format.url,
              mimeType: format.mime_type,
              bitrate: format.bitrate,
              durationSeconds: Math.round(
                (format.approx_duration_ms ?? 0) / 1000,
              ),
              mediaType,
            },
          };
        } catch (error) {
          lastFailure = error;
        }
      }
    }

    if (/unplayable|login required|no matching formats|streaming data not available/i.test(
      lastFailure?.message ?? '',
    )) {
      throw new SidecarError(
        'PLAYBACK_UNAVAILABLE',
        mediaType === 'video'
          ? 'YouTube did not provide a playable video stream.'
          : 'YouTube did not provide an audio stream for this track.',
        describeUpstreamError(lastFailure),
      );
    }
    throw new SidecarError(
      'PLAYBACK_RESOLUTION_FAILED',
      'Unable to prepare this track for playback.',
      describeUpstreamError(lastFailure),
    );
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
      return {
        path: outputPath,
        mimeType: format.mime_type,
        artworkUrl:
          largestArtworkThumbnail(
            thumbnailCandidates(info?.basic_info ?? info),
          )?.url ?? null,
      };
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

  async downloadMediaBundle(videoId, directory, metadata = {}) {
    this.#requireAuthentication();
    if (!/^[A-Za-z0-9_-]+$/.test(videoId ?? '')) {
      throw new SidecarError(
        'INVALID_VIDEO_ID',
        'A valid video ID is required to download media.',
      );
    }
    if (typeof directory !== 'string' || directory.trim().length === 0) {
      throw new SidecarError(
        'INVALID_DOWNLOAD_DIRECTORY',
        'A download directory is required.',
      );
    }

    const root = path.resolve(directory);
    const bundlePath = path.join(root, videoId);
    const stagingPath = path.join(root, `${videoId}.part`);
    let diagnosticStage = 'download.bundle.prepare';
    try {
      await mkdir(root, { recursive: true });
      await rm(stagingPath, { recursive: true, force: true });
      await mkdir(stagingPath, { recursive: true });

      diagnosticStage = 'download.bundle.audio';
      const audio = await this.downloadAudio(videoId, stagingPath);
      const extension = audioExtension(audio.mimeType);
      const stagedAudioPath = path.join(stagingPath, `audio.${extension}`);
      await rename(audio.path, stagedAudioPath);

      diagnosticStage = 'download.bundle.artwork';
      const artworkUrl =
        normalizeArtworkUrl(metadata?.artworkUrl) ??
        normalizeArtworkUrl(audio.artworkUrl);
      if (!artworkUrl) {
        throw new SidecarError(
          'DOWNLOAD_ARTWORK_UNAVAILABLE',
          'Artwork is unavailable for this track.',
          { diagnosticStage },
        );
      }
      const artworkResponse = await this.fetch(artworkUrl, {
        signal: AbortSignal.timeout(15000),
      });
      if (!artworkResponse?.ok) {
        throw new SidecarError(
          'DOWNLOAD_ARTWORK_FAILED',
          'Unable to download this track artwork.',
          {
            diagnosticStage,
            statusCode: artworkResponse?.status,
          },
        );
      }
      const artworkContentType = artworkResponse.headers
        ?.get?.('content-type')
        ?.split(';', 1)[0]
        ?.trim()
        ?.toLowerCase();
      if (artworkContentType && !artworkContentType.startsWith('image/')) {
        throw new SidecarError(
          'DOWNLOAD_ARTWORK_FAILED',
          'The downloaded artwork has an invalid content type.',
          { diagnosticStage },
        );
      }
      const artworkBytes = Buffer.from(await artworkResponse.arrayBuffer());
      if (artworkBytes.length === 0 || artworkBytes.length > 20 * 1024 * 1024) {
        throw new SidecarError(
          'DOWNLOAD_ARTWORK_FAILED',
          'The downloaded artwork is invalid.',
          { diagnosticStage },
        );
      }
      const artworkExtension = imageExtension(
        artworkContentType,
        artworkUrl,
      );
      const stagedArtworkPath = path.join(
        stagingPath,
        `cover.${artworkExtension}`,
      );
      await writeFile(stagedArtworkPath, artworkBytes);

      diagnosticStage = 'download.bundle.lyrics';
      const lyrics = await this.getLyrics(videoId, metadata);
      const stagedLyricsPath = path.join(stagingPath, 'lyrics.lrc');
      await writeFile(stagedLyricsPath, encodeLrc(lyrics.lines), 'utf8');

      diagnosticStage = 'download.bundle.metadata';
      await writeFile(
        path.join(stagingPath, 'metadata.json'),
        JSON.stringify({
          version: 1,
          videoId,
          title: stringMetadata(metadata?.title),
          artist: stringMetadata(metadata?.artist),
          album: stringMetadata(metadata?.album),
          durationSeconds: Number.isInteger(metadata?.durationSeconds)
            ? metadata.durationSeconds
            : 0,
          mimeType: audio.mimeType,
          audioFile: path.basename(stagedAudioPath),
          artworkFile: path.basename(stagedArtworkPath),
          lyricsFile: path.basename(stagedLyricsPath),
          lyricsSource: lyrics.source ?? 'none',
          downloadedAt: new Date(this.now()).toISOString(),
        }),
        'utf8',
      );

      diagnosticStage = 'download.bundle.commit';
      await rm(bundlePath, { recursive: true, force: true });
      await rename(stagingPath, bundlePath);
      return {
        bundlePath,
        path: path.join(bundlePath, path.basename(stagedAudioPath)),
        artworkPath: path.join(
          bundlePath,
          path.basename(stagedArtworkPath),
        ),
        lyricsPath: path.join(bundlePath, path.basename(stagedLyricsPath)),
        mimeType: audio.mimeType,
      };
    } catch (error) {
      await rm(stagingPath, { recursive: true, force: true });
      if (error instanceof SidecarError) {
        throw error;
      }
      throw new SidecarError(
        'DOWNLOAD_BUNDLE_FAILED',
        'Unable to complete this offline download.',
        {
          diagnosticStage,
          ...describeUpstreamError(error),
        },
      );
    }
  }

  async getFeedBrowse(itemType, id, params) {
    this.#requireAuthentication();
    if (
      !['artist', 'category', 'channel', 'podcast', 'subscriber'].includes(
        itemType,
      ) ||
      !id
    ) {
      throw new SidecarError(
        'INVALID_FEED_ITEM',
        'This feed item cannot be opened as a browse page.',
      );
    }

    let page;
    let rawArtistPage;
    let rawChartPage;
    let podcastLibraryId;
    try {
      if (itemType === 'podcast') {
        const resolved = await executeRawBrowseWithResolution(
          this.innertube.actions,
          {
            browseId: id,
            ...(params ? { params } : {}),
          },
        );
        page = resolved.response;
        podcastLibraryId = rawPodcastLibraryId(
          page?.data ?? page,
          resolved.browseId,
        );
      } else if (itemType === 'artist') {
        page = await this.#getRawArtistBrowsePage(id, params);
      } else if (itemType === 'category' && id === 'FEmusic_charts') {
        rawChartPage = await this.innertube.actions.execute('browse', {
          browseId: id,
          ...(params ? { params } : {}),
          client: 'YTMUSIC',
        });
        page = Parser.parseResponse(rawChartPage?.data ?? rawChartPage);
      } else {
        page = await this.innertube.actions.execute('browse', {
            browseId: id,
            ...(params ? { params } : {}),
            client: 'YTMUSIC',
            parse: true,
          });
      }
      if (itemType === 'artist') {
        rawArtistPage = page;
        page = Parser.parseResponse(rawArtistPage?.data ?? rawArtistPage);
      }
    } catch (error) {
      throw feedFailure(
        'BROWSE_REQUEST_FAILED',
        'Unable to load this page.',
        'browse.request',
        error,
      );
    }
    try {
      if (itemType === 'podcast') {
        const podcast = mapRawPodcastShowDetail(page?.data ?? page);
        this.podcastBrowseId = id;
        this.podcastBrowseContinuation = podcast.continuation;
        return {
          podcast: {
            id,
            libraryId: podcastLibraryId || id,
            title: podcast.title,
            subtitle: podcast.subtitle,
            description: podcast.description,
            thumbnailUrl: podcast.thumbnailUrl,
            episodes: podcast.episodes,
            hasMore: this.podcastBrowseContinuation !== null,
          },
        };
      }
      const sections = mapBrowseFeedSections(
        page,
        rawArtistPage?.data ??
          rawArtistPage ??
          rawChartPage?.data ??
          rawChartPage ??
          page?.data ??
          page,
      );
      if (itemType === 'artist') {
        const rawArtist = rawArtistPage?.data ?? rawArtistPage;
        this.#rememberArtistSubscriptionButton(rawArtist, id);
        return { artist: mapRawArtistDetail(rawArtist), sections };
      }
      return { sections };
    } catch (error) {
      throw feedFailure(
        'BROWSE_PARSE_FAILED',
        'Unable to read this page.',
        'browse.parse',
        error,
      );
    }
  }

  async getMoreFeedBrowse(itemType, id) {
    this.#requireAuthentication();
    if (itemType !== 'podcast' || !id) {
      throw new SidecarError(
        'INVALID_FEED_ITEM',
        'This feed item does not support browse continuation.',
      );
    }
    if (
      id !== this.podcastBrowseId ||
      this.podcastBrowseContinuation === null
    ) {
      return { episodes: [], hasMore: false };
    }

    try {
      const page = await this.innertube.actions.execute('/browse', {
        client: 'YTMUSIC',
        continuation: this.podcastBrowseContinuation,
      });
      if (page?.success === false) {
        throw httpResponseError(page.status_code);
      }
      const continuation = mapRawPodcastShowContinuation(page?.data ?? page);
      this.podcastBrowseContinuation = continuation.continuation;
      return {
        episodes: continuation.episodes,
        hasMore: this.podcastBrowseContinuation !== null,
      };
    } catch (error) {
      if (/continuation did not have any content|continuation not found/i.test(
        error?.message ?? '',
      )) {
        this.podcastBrowseContinuation = null;
        return { episodes: [], hasMore: false };
      }
      throw feedFailure(
        'BROWSE_CONTINUATION_FAILED',
        'Unable to load more podcast episodes.',
        'browse.continuation',
        error,
      );
    }
  }

  async #createSession(cookie) {
    this.cookie = cookie ?? null;
    this.innertube = await this.createInnertube(this.cookie, this.locale);
    this.authMode = this.cookie ? 'cookie' : null;
    this.homeFeed = null;
    this.homeRootFeed = null;
    this.homeFilters = [];
    this.exploreContinuation = null;
    this.podcastBrowseId = null;
    this.podcastBrowseContinuation = null;
    this.playlistPages.clear();
    this.specialCollectionPages.clear();
    this.historyContinuation = null;
    this.historySeenVideoIds.clear();
    this.artistSubscriptionButtons.clear();
    this.albumLibraryTargets.clear();
    this.nextAccountWriteAt = 0;
  }

  async #libraryFilter(library, kind) {
    const filter = libraryFilterLabel(library?.filters, kind);
    if (kind === 'albums' && this.innertube.actions?.execute) {
      let browseError;
      try {
        return await this.#loadLibraryBrowse('FEmusic_liked_albums');
      } catch (error) {
        browseError = error;
      }

      if (filter) {
        try {
          const filtered = await this.#libraryFilterViaChip(library, filter);
          if (filtered) return filtered;
        } catch {
          // The dedicated Albums browse error remains the useful failure.
        }
        try {
          return await library.applyFilter(filter);
        } catch {
          throw browseError;
        }
      }
      throw browseError;
    }
    if (filter) {
      try {
        return await library.applyFilter(filter);
      } catch (error) {
        if (
          !/Expected an api_url, but none was found/i.test(
            error?.message ?? '',
          )
        ) {
          throw error;
        }
        const filtered = await this.#libraryFilterViaChip(library, filter);
        if (filtered) return filtered;
        throw error;
      }
    }
    return ['podcasts', 'albums'].includes(kind) ? null : library;
  }

  async #loadLibraryBrowse(browseId) {
    return this.#loadRawLibraryAlbumsPage({ browseId });
  }

  async #libraryFilterViaChip(library, filter) {
    const chipCloud = library.page?.contents_memo?.getType(
      YTNodes.ChipCloud,
    )?.[0];
    const chip = listOf(chipCloud?.chips).find(
      (candidate) => candidate?.text === filter,
    );
    const reloadCommand = listOf(chip?.endpoint?.payload?.commands)
      .find((command) => command?.browseSectionListReloadEndpoint)
      ?.browseSectionListReloadEndpoint;
    const continuation =
      reloadCommand?.continuation?.reloadContinuationData?.continuation;
    if (!continuation) return null;

    return this.#loadLibraryReloadPage(continuation);
  }

  async #loadLibraryReloadPage(continuation) {
    return this.#loadRawLibraryAlbumsPage({ continuation });
  }

  async #loadRawLibraryAlbumsPage(request) {
    const response = await executeRawBrowse(
      this.innertube.actions,
      request,
    );
    return rawLibraryAlbumsPage(response?.data ?? response, (continuation) =>
      this.#loadRawLibraryAlbumsPage({ continuation }));
  }

  async #loadLibrarySection(
    library,
    kind,
    collect,
    { required = false } = {},
  ) {
    let diagnosticStage = `library.filter.${kind}`;
    try {
      const page = await this.#libraryFilter(library, kind);
      diagnosticStage = `library.collect.${kind}`;
      return await collect(page);
    } catch (error) {
      const details = {
        ...describeUpstreamError(error),
        diagnosticStage,
      };
      if (required) {
        throw new SidecarError(
          'LIBRARY_LOAD_FAILED',
          'Unable to load your YouTube media library.',
          details,
        );
      }
      this.emit('library.section_unavailable', {
        method: 'library.media',
        code: 'LIBRARY_SECTION_UNAVAILABLE',
        ...details,
      });
      return [];
    }
  }

  async #collectLibraryItems(page, mapper, identity) {
    const items = [];
    const seen = new Set();
    const seenPages = new Set();
    const seenContinuations = new Set();
    for (let index = 0; index < MAX_LIBRARY_PAGES && page; index += 1) {
      if (seenPages.has(page)) break;
      seenPages.add(page);
      for (const [itemIndex, item] of collectItems(page.contents).entries()) {
        const mapped = mapper(item, itemIndex);
        if (!mapped) continue;
        const key = identity(mapped);
        if (seen.has(key)) continue;
        seen.add(key);
        items.push(mapped);
      }
      if (!page.has_continuation) break;
      const continuation = libraryContinuationIdentity(page);
      if (continuation && seenContinuations.has(continuation)) break;
      if (continuation) seenContinuations.add(continuation);
      page = await page.getContinuation();
    }
    return items;
  }

  async #collectPodcastLibraryShows(page) {
    const podcasts = [];
    const seenPodcastIds = new Set();
    const seenPages = new Set();
    const seenContinuations = new Set();
    for (let index = 0; index < MAX_LIBRARY_PAGES && page; index += 1) {
      if (seenPages.has(page)) break;
      seenPages.add(page);
      for (const [itemIndex, item] of collectItems(page.contents).entries()) {
        const podcast = mapFeedItem(item, 0, itemIndex);
        if (
          podcast?.itemType === 'podcast' &&
          !seenPodcastIds.has(podcast.id)
        ) {
          seenPodcastIds.add(podcast.id);
          podcasts.push(podcast);
        }
      }
      if (!page.has_continuation) break;
      const continuation = libraryContinuationIdentity(page);
      if (continuation && seenContinuations.has(continuation)) break;
      if (continuation) seenContinuations.add(continuation);
      page = await page.getContinuation();
    }
    return podcasts;
  }

  async #getSpecialCollectionSummaries() {
    try {
      const library = await this.innertube.getLibrary();
      return [
        mapSpecialLibraryCollection('liked_videos', library.liked_videos),
      ].filter(Boolean);
    } catch {
      // Standard YouTube Library shelves are optional for a Music session.
      return [];
    }
  }

  #startPlaylistPage(id, playlist, page, states) {
    const tracks = [];
    const seenVideoIds = new Set();
    appendUniqueTracks(
      tracks,
      listOf(page?.items).map(mapTrack).filter(Boolean),
      seenVideoIds,
    );
    if (page?.has_continuation === true) {
      states.set(id, { page, seenVideoIds });
    } else {
      states.delete(id);
    }
    return {
      playlist,
      tracks,
      hasMore: page?.has_continuation === true,
    };
  }

  async #getMorePlaylistPage(id, states) {
    const state = states.get(id);
    if (!state?.page?.has_continuation) {
      return { tracks: [], hasMore: false };
    }

    try {
      const page = await state.page.getContinuation();
      const tracks = [];
      const appended = appendUniqueTracks(
        tracks,
        listOf(page?.items).map(mapTrack).filter(Boolean),
        state.seenVideoIds,
      );
      const hasMore = appended && page?.has_continuation === true;
      if (hasMore) {
        states.set(id, { ...state, page });
      } else {
        states.delete(id);
      }
      return { tracks, hasMore };
    } catch (error) {
      if (isContinuationExhausted(error)) {
        states.delete(id);
        return { tracks: [], hasMore: false };
      }
      throw error;
    }
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
    try {
      return await this.#writeGenericRating(videoId, rating);
    } catch {
      // The generic InteractionManager uses the TV client. Some Cookie
      // sessions only expose the action endpoints embedded in a web watch
      // response, so retry once through the video's own control metadata.
      const info = await this.innertube.getInfo(videoId, { client: 'WEB' });
      switch (rating) {
        case 'like':
          return info.like();
        case 'dislike':
          return info.dislike();
        case 'none':
          return info.removeRating();
      }
    }
  }

  async #writeGenericRating(videoId, rating) {
    switch (rating) {
      case 'like':
        return this.innertube.interact.like(videoId);
      case 'dislike':
        return this.innertube.interact.dislike(videoId);
      case 'none':
        return this.innertube.interact.removeRating(videoId);
    }
  }

  async #writeSubscription(channelId, subscribed) {
    return this.#writeArtistSubscription(channelId, subscribed);
  }

  async #writeArtistSubscription(channelId, subscribed) {
    let button = this.artistSubscriptionButtons.get(channelId);
    if (!button) {
      try {
        const artist = await this.innertube.music.getArtist(channelId);
        button = artist.header?.subscription_button;
      } catch {
        // The raw YT Music browse response below is the authoritative fallback.
      }
    }
    if (
      !button ||
      (button.subscribed !== subscribed &&
          subscriptionActionEndpoint(button, subscribed) == null)
    ) {
      button = await this.#loadRawArtistSubscriptionButton(channelId) ?? button;
    }
    const resolvedChannelId = button?.channel_id;
    if (!resolvedChannelId) {
      throw new Error('The artist page did not provide a canonical channel ID.');
    }
    if (button.subscribed === subscribed) {
      return { channelId: resolvedChannelId, subscribed };
    }
    const endpoint = subscriptionActionEndpoint(button, subscribed);
    const response = endpoint
      ? await endpoint.call(this.innertube.actions, {
          client: 'YTMUSIC',
        })
      : await this.#writeCanonicalArtistSubscription(
          resolvedChannelId,
          subscribed,
        );
    if (response?.success === false) {
      throw httpResponseError(
        response.status_code,
        'YouTube subscription update',
      );
    }
    this.artistSubscriptionButtons.clear();
    return { channelId: resolvedChannelId, subscribed };
  }

  async #writeCanonicalArtistSubscription(channelId, subscribed) {
    return this.innertube.actions.execute(
      subscribed ? 'subscription/subscribe' : 'subscription/unsubscribe',
      {
        channelIds: [channelId],
        params: subscribed
            ? ARTIST_SUBSCRIBE_PARAMS
            : ARTIST_UNSUBSCRIBE_PARAMS,
        client: 'YTMUSIC',
      },
    );
  }

  async #loadRawArtistSubscriptionButton(channelId) {
    const page = await this.#getRawArtistBrowsePage(channelId);
    return this.#rememberArtistSubscriptionButton(page?.data ?? page, channelId);
  }

  #rememberArtistSubscriptionButton(page, requestedChannelId) {
    const rawButton = rawArtistSubscriptionButton(page);
    if (!rawButton) return null;
    const button = new YTNodes.SubscribeButton(rawButton);
    if (!button.channel_id) return null;
    this.artistSubscriptionButtons.set(button.channel_id, button);
    if (requestedChannelId && requestedChannelId !== button.channel_id) {
      this.artistSubscriptionButtons.set(requestedChannelId, button);
    }
    return button;
  }

  async #getRawArtistBrowsePage(id, params) {
    return executeRawBrowse(this.innertube.actions, {
      browseId: id,
      ...(params ? { params } : {}),
    });
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
    owner: nullableMetadataText(
      item?.author?.name ?? metadataText(item?.metadata?.metadata),
    ),
    itemCount: nullableMetadataText(item?.video_count ?? item?.item_count),
    thumbnailUrl: largestArtworkThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

function mapFollowedArtist(item, index) {
  const artist = mapFeedItem(item, 0, index);
  return artist?.itemType === 'artist' ? artist : null;
}

function mapLibraryAlbum(item, index) {
  const album = mapFeedItem(item, 0, index);
  if (!album) return null;
  return {
    ...album,
    itemType: 'album',
    videoId: null,
  };
}

function rawLibraryAlbumsPage(page, loadContinuation) {
  const items = collectRawRenderers(page, [
    'musicTwoRowItemRenderer',
    'musicResponsiveListItemRenderer',
  ])
    .map(mapRawLibraryAlbum)
    .filter(Boolean);
  const continuation = findRawContinuationToken(page);
  return {
    contents: [{ contents: items }],
    has_continuation: Boolean(continuation),
    continuation,
    ...(continuation
      ? { getContinuation: () => loadContinuation(continuation) }
      : {}),
  };
}

function libraryContinuationIdentity(page) {
  if (typeof page?.continuation === 'string') {
    return page.continuation;
  }
  return listOf(page?.contents).find(
    (content) => typeof content?.continuation === 'string',
  )?.continuation ?? null;
}

function mapRawLibraryAlbum(renderer) {
  const flexColumns = listOf(renderer?.flexColumns);
  const titleValue =
    renderer?.title ??
    flexColumns[0]?.musicResponsiveListItemFlexColumnRenderer?.text;
  const subtitleValue =
    renderer?.subtitle ??
    renderer?.secondTitle ??
    flexColumns[1]?.musicResponsiveListItemFlexColumnRenderer?.text;
  const browse = rawAlbumBrowseEndpoint(renderer, titleValue);
  const title = rawTextValue(titleValue);
  if (!browse || !title) return null;

  const subtitle = rawTextValue(subtitleValue);
  const artists = rawAlbumArtists(subtitleValue, subtitle);
  return {
    item_type: 'album',
    id: browse.browseId,
    title,
    subtitle: subtitle || null,
    artists,
    thumbnails: rawThumbnailCandidates(renderer),
    endpoint: {
      payload: {
        browseId: browse.browseId,
        ...(typeof browse.params === 'string'
          ? { params: browse.params }
          : {}),
      },
    },
  };
}

function rawAlbumBrowseEndpoint(renderer, titleValue) {
  const candidates = [
    ...listOf(titleValue?.runs).map(
      (run) => run?.navigationEndpoint?.browseEndpoint,
    ),
    renderer?.navigationEndpoint?.browseEndpoint,
  ];
  return candidates.find((candidate) =>
    isAlbumBrowseId(candidate?.browseId));
}

function isAlbumBrowseId(value) {
  return typeof value === 'string' &&
    (value.startsWith('MPR') ||
      value.startsWith('FEmusic_library_privately_owned_release'));
}

function rawAlbumArtists(subtitleValue, subtitle) {
  const artists = listOf(subtitleValue?.runs)
    .filter((run) => {
      const browse = run?.navigationEndpoint?.browseEndpoint;
      const pageType =
        browse?.browseEndpointContextSupportedConfigs
          ?.browseEndpointContextMusicConfig?.pageType;
      return typeof browse?.browseId === 'string' &&
        (browse.browseId.startsWith('UC') ||
          ['MUSIC_PAGE_TYPE_ARTIST', 'MUSIC_PAGE_TYPE_USER_CHANNEL'].includes(
            pageType,
          ));
    })
    .map((run) => rawTextValue(run))
    .filter(Boolean);
  return artists.length
    ? [...new Set(artists)]
    : artistsFromSubtitle(subtitle);
}

function mapSpecialLibraryCollection(kind, section) {
  if (!section) return null;
  const title = textValue(section.title) || specialCollectionTitle(kind);
  if (!title) return null;
  return {
    id: kind,
    specialKind: kind,
    title,
  };
}

function specialCollectionTitle(kind) {
  return kind === 'liked_videos' ? 'Liked videos' : '';
}

function normalizeSpecialCollectionKind(value) {
  return value === 'liked_videos' ? value : null;
}

function libraryFilterLabel(filters, kind) {
  const labels = {
    playlists: ['playlists', '播放列表'],
    artists: ['artists', 'artist', '艺人', '艺术家', '歌手'],
    podcasts: ['podcasts', 'podcast', '播客', '播客节目'],
    albums: ['albums', 'album', '专辑', '專輯'],
  }[kind] ?? [];
  for (const filter of listOf(filters)) {
    const label = textValue(filter);
    if (label && labels.includes(label.toLowerCase())) {
      return label;
    }
  }
  return null;
}

export function mapTrack(item) {
  const type = item?.type ?? item?.constructor?.type ?? item?.constructor?.name;
  const rawItemType = item?.item_type ?? item?.content_type;
  const itemType = typeof rawItemType === 'string'
    ? rawItemType.toLowerCase()
    : null;
  if (
    !item ||
    !['episode', 'song', 'video', 'non_music_track'].includes(itemType) &&
      !['PlaylistVideo', 'LockupView', 'Video'].includes(type)
  ) {
    return null;
  }
  const videoId = item.id ?? item.content_id ?? item.endpoint?.payload?.videoId;
  const title = textValue(item.title ?? item.metadata?.title);
  if (!videoId || !title) return null;

  const subtitle = nullableMetadataText(
    item.subtitle ?? item.second_title ?? item.description,
  );
  const artists = listOf(
    item.artists ?? item.authors ?? (item.author ? [item.author] : []),
  );
  const artistNames = artists
    .map((artist) => nullableMetadataText(artist?.name ?? artist))
    .filter(Boolean);
  const parsedDurationSeconds = Number(item.duration?.seconds);
  const durationSeconds =
    Number.isFinite(parsedDurationSeconds) && parsedDurationSeconds > 0
      ? Math.round(parsedDurationSeconds)
      : durationSecondsFromRawText(
          textValue(item.duration) ??
            textValue(item.length_text) ??
            textValue(item.second_title) ??
            subtitle,
        );
  return {
    videoId,
    itemType: itemType ?? 'song',
    title,
    artists: artistNames.length ? artistNames : artistsFromSubtitle(subtitle),
    album:
      nullableMetadataText(item.album?.name ?? item.album) ??
      albumFromSubtitle(subtitle),
    durationSeconds,
    thumbnailUrl: largestArtworkThumbnail(thumbnailCandidates(item))?.url ?? null,
  };
}

function mapHistoryPage(page) {
  const continuation = page?.continuation_contents?.as(
    MusicShelfContinuation,
    SectionListContinuation,
  );
  if (continuation) {
    return {
      tracks: flattenedMusicItems(continuation.contents)
        .map(mapTrack)
        .filter(Boolean),
      continuation: continuation.continuation ?? null,
    };
  }

  const shelves = page?.contents_memo?.getType(YTNodes.MusicShelf) ?? [];
  return {
    tracks: shelves.flatMap((shelf) => listOf(shelf.contents))
      .map(mapTrack)
      .filter(Boolean),
    continuation:
      shelves.find((shelf) => shelf.continuation)?.continuation ?? null,
  };
}

function flattenedMusicItems(contents) {
  return listOf(contents).flatMap((item) => {
    const nested = listOf(item?.contents);
    return nested.length ? nested : [item];
  });
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
      const title = textValue(section?.header?.title ?? section?.title);
      const subtitle = nullableMetadataText(section?.header?.strapline);
      const items = listOf(section?.contents)
        .map((item, itemIndex) => mapFeedItem(item, sectionIndex, itemIndex))
        .filter(Boolean);
      const itemsPerColumn = Number.isInteger(section?.num_items_per_column)
        ? Math.max(1, section.num_items_per_column)
        : 1;
      return title && items.length
        ? {
            title,
            ...(subtitle ? { subtitle } : {}),
            ...(itemsPerColumn > 1 ? { itemsPerColumn } : {}),
            items,
          }
        : null;
    })
    .filter(Boolean);
}

function mapExploreFeedSections(
  feed,
  locale,
  rawPage = feed?.page,
) {
  const contentSections = applyRawSectionChartMetadata(
    mapFeedSections(feed?.sections),
    rawPage,
  );
  const navigationByIdentity = new Map();
  for (const [index, button] of listOf(feed?.top_buttons).entries()) {
    const item = mapFeedItem(button, 0, index);
    if (item?.itemType !== 'category') continue;
    navigationByIdentity.set(feedItemIdentity(item), item);
  }

  const hasCharts = [...navigationByIdentity.values()].some(
    (item) => item.id === 'FEmusic_charts',
  );
  if (!hasCharts) {
    const charts = {
      id: 'FEmusic_charts',
      itemType: 'category',
      title: locale?.toLowerCase().startsWith('zh') ? '排行榜' : 'Charts',
      subtitle: null,
      videoId: null,
      artists: [],
      album: null,
      durationSeconds: 0,
      thumbnailUrl: null,
    };
    navigationByIdentity.set(feedItemIdentity(charts), charts);
  }

  const navigationItems = [...navigationByIdentity.values()];
  const navigationIdentities = new Set(navigationByIdentity.keys());
  const deduplicatedSections = contentSections
    .map((section) => {
      const items = section.items.filter(
        (item) =>
          item.itemType !== 'category' ||
          !navigationIdentities.has(feedItemIdentity(item)),
      );
      return items.length === section.items.length
        ? section
        : items.length
          ? { ...section, items }
          : null;
    })
    .filter(Boolean);

  return [
    {
      title: locale?.toLowerCase().startsWith('zh') ? '探索' : 'Explore',
      items: navigationItems,
    },
    ...deduplicatedSections,
  ];
}

function feedItemIdentity(item) {
  return `${item.id}\u0000${item.browseParams ?? ''}`;
}

function albumAudioPlaylistId(album) {
  let playlistId = null;
  walkRawJson(album?.header, (key, candidate) => {
    if (
      key === 'playlistId' &&
      typeof candidate === 'string' &&
      candidate.startsWith('OLAK')
    ) {
      playlistId = candidate;
      return true;
    }
    return false;
  });
  return playlistId;
}

export function mapSearchItems(rawSections) {
  const seen = new Set();
  return collectItems(arrayOf(rawSections))
    .map((item, index) => mapFeedItem(item, 0, index))
    .filter((item) => {
      if (!item) return false;
      if (item.itemType === 'unknown') return false;
      const key = `${item.itemType}:${item.id}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 40);
}

export function mapBrowseFeedSections(page, rawPage = page?.data ?? page) {
  const withChartMetadata = (sections) =>
    applyRawSectionChartMetadata(sections, rawPage);
  const contents = page?.contents;
  const root = typeof contents?.item === 'function' ? contents.item() : contents;
  const tabs = listOf(root?.tabs);
  const tab = tabs.find((candidate) => candidate?.selected) ?? tabs[0];
  for (const candidate of [tab?.content?.contents, root?.contents]) {
    const sections = mapFeedSections(candidate);
    if (sections.length) return withChartMetadata(sections);
  }

  const memo = page?.contents_memo;
  if (typeof memo?.getType !== 'function') return [];

  const shelves = memo.getType(
    YTNodes.MusicShelf,
    YTNodes.MusicCarouselShelf,
    YTNodes.MusicPlaylistShelf,
  );
  const shelfSections = mapFeedSections(shelves);
  if (shelfSections.length) return withChartMetadata(shelfSections);

  const items = memo
    .getType(YTNodes.MusicMultiRowListItem, YTNodes.MusicResponsiveListItem)
    .map((item, index) => mapFeedItem(item, 0, index))
    .filter(Boolean);
  if (!items.length) return [];

  const header = memo.getType(YTNodes.MusicResponsiveHeader)?.[0];
  return withChartMetadata([
    {
      title: textValue(header?.title) || 'Episodes',
      items,
    },
  ]);
}

function applyRawChartMetadata(sections, rawPage) {
  const metadataByIdentity = rawChartMetadataByIdentity(rawPage);
  if (!metadataByIdentity.size) return sections;

  return sections.map((section) => {
    let changed = false;
    const items = section.items.map((item) => {
      const metadata =
        metadataByIdentity.get(item.videoId) ??
        metadataByIdentity.get(item.id) ??
        metadataByIdentity.get(normalizePlaylistId(item.id));
      if (!metadata) return item;
      changed = true;
      return { ...item, ...metadata };
    });
    return changed ? { ...section, items } : section;
  });
}

function applyRawSectionChartMetadata(sections, rawPage) {
  const rawSectionsByTitle = new Map();
  for (const rawSection of collectRawRenderers(
    rawPage,
    ['musicCarouselShelfRenderer'],
    200,
  )) {
    const title = rawTextValue(
      rawSection?.header?.musicCarouselShelfBasicHeaderRenderer?.title ??
        rawSection?.header?.musicCarouselShelfHeaderRenderer?.title ??
        rawSection?.header?.title ??
        rawSection?.title,
    );
    if (!title) continue;
    const matchingSections = rawSectionsByTitle.get(title) ?? [];
    matchingSections.push(rawSection);
    rawSectionsByTitle.set(title, matchingSections);
  }
  if (!rawSectionsByTitle.size) {
    return applyRawChartMetadata(sections, rawPage);
  }

  return sections.map((section) => {
    const rawSection = rawSectionsByTitle.get(section.title)?.shift();
    return rawSection
      ? applyRawChartMetadata([section], rawSection)[0]
      : section;
  });
}

function rawChartMetadataByIdentity(rawPage) {
  const metadataByIdentity = new Map();
  const renderers = collectRawRenderers(
    rawPage,
    ['musicResponsiveListItemRenderer', 'musicTwoRowItemRenderer'],
    200,
  );
  for (const renderer of renderers) {
    const indexRenderer =
      renderer?.customIndexColumn?.musicCustomIndexColumnRenderer;
    const rank = chartRankValue(indexRenderer?.text);
    if (rank === null) continue;

    const trend = chartTrendValue(
      indexRenderer?.icon?.iconType ?? indexRenderer?.icon?.icon_type,
    );
    const identities = new Set(
      collectRawValuesForKey(renderer, 'videoId').filter(
        (value) => typeof value === 'string' && value.length,
      ),
    );
    const browseId = rawChartPrimaryBrowseId(renderer);
    if (browseId) {
      identities.add(browseId);
      identities.add(normalizePlaylistId(browseId));
    }
    for (const identity of identities) {
      if (!identity) continue;
      metadataByIdentity.set(identity, {
        rank,
        ...(trend ? { trend } : {}),
      });
    }
  }
  return metadataByIdentity;
}

function rawChartPrimaryBrowseId(renderer) {
  const directBrowseId =
    renderer?.navigationEndpoint?.browseEndpoint?.browseId ??
    renderer?.navigation_endpoint?.browse_endpoint?.browse_id;
  if (typeof directBrowseId === 'string' && directBrowseId.length) {
    return directBrowseId;
  }

  const firstFlexColumn = arrayOf(
    renderer?.flexColumns ?? renderer?.flex_columns,
  )[0];
  const titleColumn =
    firstFlexColumn?.musicResponsiveListItemFlexColumnRenderer ??
    firstFlexColumn?.music_responsive_list_item_flex_column_renderer;
  return collectRawValuesForKey(titleColumn?.text ?? titleColumn, 'browseId')
    .find((value) => typeof value === 'string' && value.length) ?? null;
}

function chartRankValue(value) {
  const text = rawTextValue(value) ?? textValue(value);
  const match = text?.match(/\d+/);
  if (!match) return null;
  const rank = Number.parseInt(match[0], 10);
  return Number.isInteger(rank) && rank > 0 ? rank : null;
}

function chartTrendValue(value) {
  if (typeof value !== 'string') return null;
  const iconType = value.toUpperCase();
  if (iconType.includes('NEUTRAL')) return 'neutral';
  if (iconType.endsWith('_UP') || iconType.includes('TRENDING_UP')) {
    return 'up';
  }
  if (iconType.endsWith('_DOWN') || iconType.includes('TRENDING_DOWN')) {
    return 'down';
  }
  return null;
}

function rawPodcastLibraryId(page, resolvedBrowseId) {
  const headers = collectRawRenderers(page, [
    'musicResponsiveHeaderRenderer',
    'musicDetailHeaderRenderer',
    'musicEditablePlaylistDetailHeaderRenderer',
  ]);
  const candidates = [
    resolvedBrowseId,
    ...headers.flatMap((header) => collectRawValuesForKey(header, 'playlistId')),
  ];
  for (const candidate of candidates) {
    const playlistId = normalizePlaylistId(candidate);
    if (playlistId.startsWith('PL')) return playlistId;
  }
  return '';
}

export function mapRawPodcastShowDetail(page, fallbackTitle = 'Podcast') {
  const episodePage = findRawPodcastEpisodePage(page, {
    allowResponsiveItems: true,
  });
  const header = collectRawRenderers(page, [
    'musicResponsiveHeaderRenderer',
    'musicDetailHeaderRenderer',
    'musicEditablePlaylistDetailHeaderRenderer',
    'musicImmersiveHeaderRenderer',
  ])
    .map(unwrapRawPodcastHeader)
    .find((candidate) => rawTextValue(candidate?.title));
  return {
    title: rawTextValue(header?.title) || fallbackTitle,
    subtitle:
      rawTextValue(
        header?.straplineTextOne ??
          header?.straplineTextOne?.runs ??
          header?.subtitle,
      ) || null,
    description:
      rawTextValue(
        header?.description?.musicDescriptionShelfRenderer?.description ??
          header?.description,
      ) || null,
    thumbnailUrl:
      largestArtworkThumbnail(rawThumbnailCandidates(header))?.url ?? null,
    episodes: episodePage?.episodes ?? [],
    continuation: episodePage?.continuation ?? null,
  };
}

export function mapRawArtistDetail(page, fallbackTitle = 'Artist') {
  const header = rawArtistHeader(page);
  const subscribeButton = rawArtistSubscriptionButton(page);
  return {
    title: rawTextValue(header?.title) || fallbackTitle,
    subtitle:
      rawTextValue(
        header?.subtitle ??
          header?.straplineTextOne ??
          header?.monthlyListenerCount,
      ) || null,
    audience: rawArtistAudience(header),
    thumbnailUrl:
      largestArtworkThumbnail(rawThumbnailCandidates(header))?.url ?? null,
    channelId:
      typeof subscribeButton?.channelId === 'string'
        ? subscribeButton.channelId
        : null,
    subscriberCount:
      rawTextValue(
        subscribeButton?.subscriberCountText ??
          subscribeButton?.longSubscriberCountText ??
          header?.subscriberCountText,
      ) || null,
    subscribed:
      typeof subscribeButton?.subscribed === 'boolean'
        ? subscribeButton.subscribed
        : null,
  };
}

function rawArtistAudience(header) {
  const explicitAudience = rawTextValue(
    header?.monthlyListenerCount ??
      header?.monthlyListenerCountText ??
      header?.monthlyAudience,
  );
  if (explicitAudience) return explicitAudience;
  const subtitle = rawTextValue(header?.subtitle ?? header?.straplineTextOne);
  return looksLikeArtistAudience(subtitle) ? subtitle : null;
}

function looksLikeArtistAudience(value) {
  return typeof value === 'string' &&
      /monthly|audience|listener|观众|聽眾|听众|每月|月度/i.test(value);
}

function rawArtistHeader(page) {
  return collectRawRenderers(page, [
    'musicImmersiveHeaderRenderer',
    'musicVisualHeaderRenderer',
    'musicResponsiveHeaderRenderer',
  ])
    .map(unwrapRawPodcastHeader)
    .find((candidate) => rawTextValue(candidate?.title));
}

function rawArtistSubscriptionButton(page) {
  const header = rawArtistHeader(page);
  const button =
    header?.subscriptionButton?.subscribeButtonRenderer ??
    header?.subscriptionButton;
  return button && typeof button === 'object' ? button : null;
}

function subscriptionActionEndpoint(button, subscribed) {
  const endpoints = subscribed
    ? button?.on_subscribe_endpoints
    : button?.on_unsubscribe_endpoints;
  return endpoints?.[0] ?? null;
}

export function mapRawPodcastShowContinuation(page) {
  const episodePage = findRawPodcastEpisodePage(page, {
    allowResponsiveItems: true,
  });
  return {
    episodes: episodePage?.episodes ?? [],
    continuation:
      episodePage?.continuation ?? findRawContinuationToken(page) ?? null,
  };
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
  const rank = chartRankValue(item?.index);
  const durationFromText = durationSecondsFromRawText(
    textValue(item?.duration) ??
      textValue(item?.length_text) ??
      textValue(item?.second_title) ??
      subtitle,
  );
  const numericDuration = Number(item?.duration?.seconds);
  let durationSeconds = durationFromText;
  if (
    durationSeconds <= 0 &&
    Number.isFinite(numericDuration) &&
    numericDuration > 0
  ) {
    durationSeconds = Math.round(numericDuration);
  }

  return {
    id: id || `${itemType}-${sectionIndex}-${itemIndex}`,
    itemType,
    title,
    subtitle: subtitle || null,
    videoId: isTrackItemType(itemType)
      ? payload.videoId ?? item?.id ?? null
      : null,
    ...(typeof payload.params === 'string' ? { browseParams: payload.params } : {}),
    artists: resolvedArtists,
    album: textValue(item?.album?.name ?? item?.album) ?? albumFromSubtitle(subtitle),
    durationSeconds,
    thumbnailUrl: largestArtworkThumbnail(thumbnailCandidates(item))?.url ?? null,
    ...(rank !== null ? { rank } : {}),
  };
}

function findRawPodcastEpisodePage(
  page,
  { allowResponsiveItems = false } = {},
) {
  const shelves = collectRawRenderers(page, [
    'musicShelfRenderer',
    'musicPlaylistShelfRenderer',
    'musicShelfContinuation',
    'musicPlaylistShelfContinuation',
  ]);
  for (const shelf of shelves) {
    const episodePage = mapRawPodcastEpisodePage(shelf, false);
    if (episodePage) return episodePage;
  }

  if (allowResponsiveItems) {
    const playlistShelves = collectRawRenderers(page, [
      'musicPlaylistShelfRenderer',
      'musicPlaylistShelfContinuation',
      'musicShelfContinuation',
    ]);
    const responsiveShelves = playlistShelves.length
      ? playlistShelves
      : collectRawRenderers(page, ['musicShelfRenderer']);
    for (const shelf of responsiveShelves) {
      const episodePage = mapRawPodcastEpisodePage(shelf, true);
      if (episodePage) return episodePage;
    }
  }

  const continuationItems = collectRawValuesForKey(page, 'continuationItems');
  for (const items of continuationItems) {
    const episodePage = mapRawPodcastEpisodePage(
      { contents: items },
      allowResponsiveItems,
    );
    if (episodePage) return episodePage;
  }

  const rawEpisodes = collectRawRenderers(page, [
    'musicMultiRowListItemRenderer',
  ])
    .map((renderer, index) => mapRawPodcastEpisode(renderer, index))
    .filter(Boolean);
  return rawEpisodes.length
    ? {
        episodes: deduplicatePodcastEpisodes(rawEpisodes),
        continuation: findRawContinuationToken(page),
      }
    : null;
}

function mapRawPodcastEpisodePage(shelf, allowResponsiveItems) {
  const renderers = [];
  for (const item of listOf(shelf?.contents)) {
    if (item?.musicMultiRowListItemRenderer) {
      renderers.push(item.musicMultiRowListItemRenderer);
    } else if (allowResponsiveItems && item?.musicResponsiveListItemRenderer) {
      renderers.push(item.musicResponsiveListItemRenderer);
    }
  }
  const episodes = renderers
    .map((renderer, index) => mapRawPodcastEpisode(renderer, index))
    .filter(Boolean);
  if (episodes.length === 0) return null;
  return {
    episodes: deduplicatePodcastEpisodes(episodes),
    continuation: findRawContinuationToken(shelf),
  };
}

function mapRawPodcastEpisode(renderer, index) {
  const videoId = findFirstRawString(renderer, 'videoId');
  if (!videoId) return null;
  const flexColumns = listOf(renderer?.flexColumns);
  const fixedColumns = listOf(renderer?.fixedColumns);
  const title =
    rawTextValue(renderer?.title) ||
    rawTextValue(
      flexColumns[0]?.musicResponsiveListItemFlexColumnRenderer?.text,
    );
  if (!title) return null;
  const subtitle =
    rawTextValue(renderer?.secondTitle ?? renderer?.subtitle) ||
    rawTextValue(
      flexColumns[1]?.musicResponsiveListItemFlexColumnRenderer?.text,
    );
  const durationText =
    rawTextValue(renderer?.secondTitle) ||
    rawTextValue(
      fixedColumns[0]?.musicResponsiveListItemFixedColumnRenderer?.text,
    ) ||
    subtitle;
  return {
    id: videoId || `episode-0-${index}`,
    itemType: 'episode',
    title,
    subtitle: subtitle || null,
    videoId,
    artists: [],
    album: null,
    durationSeconds: durationSecondsFromRawText(durationText),
    thumbnailUrl:
      largestArtworkThumbnail(rawThumbnailCandidates(renderer))?.url ?? null,
    description: rawTextValue(renderer?.description) || null,
  };
}

function deduplicatePodcastEpisodes(episodes) {
  return [
    ...new Map(episodes.map((episode) => [episode.videoId, episode])).values(),
  ];
}

function unwrapRawPodcastHeader(header) {
  return (
    header?.header?.musicResponsiveHeaderRenderer ??
    header?.header?.musicDetailHeaderRenderer ??
    header
  );
}

function collectRawRenderers(value, rendererNames, limit = Number.POSITIVE_INFINITY) {
  const renderers = [];
  walkRawJson(value, (key, candidate) => {
    if (rendererNames.includes(key) && candidate && typeof candidate === 'object') {
      renderers.push(candidate);
      return renderers.length >= limit;
    }
    return false;
  });
  return renderers;
}

function collectRawValuesForKey(value, targetKey) {
  const values = [];
  walkRawJson(value, (key, candidate) => {
    if (key === targetKey) values.push(candidate);
    return false;
  });
  return values;
}

function walkRawJson(value, visitor, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 24) return false;
  if (Array.isArray(value)) {
    for (const item of value) {
      if (walkRawJson(item, visitor, depth + 1)) return true;
    }
    return false;
  }
  for (const [key, candidate] of Object.entries(value)) {
    if (visitor(key, candidate)) return true;
    if (walkRawJson(candidate, visitor, depth + 1)) return true;
  }
  return false;
}

function rawTextValue(value) {
  if (!value) return null;
  if (typeof value === 'string') return value.trim() || null;
  if (typeof value.simpleText === 'string') {
    return value.simpleText.trim() || null;
  }
  if (Array.isArray(value.runs)) {
    const text = value.runs
      .map((run) => (typeof run?.text === 'string' ? run.text : ''))
      .join('')
      .trim();
    return text || null;
  }
  if (value.text && value.text !== value) {
    return rawTextValue(value.text);
  }
  return null;
}

function rawThumbnailCandidates(value) {
  const thumbnails = [];
  for (const candidate of collectRawValuesForKey(value, 'thumbnails')) {
    for (const thumbnail of listOf(candidate)) {
      if (thumbnail?.url) thumbnails.push(thumbnail);
    }
  }
  return thumbnails;
}

function findFirstRawString(value, targetKey) {
  let result = null;
  walkRawJson(value, (key, candidate) => {
    if (key === targetKey && typeof candidate === 'string' && candidate) {
      result = candidate;
      return true;
    }
    return false;
  });
  return result;
}

function findRawContinuationToken(value) {
  let token = null;
  walkRawJson(value, (key, candidate) => {
    if (
      key === 'continuationCommand' &&
      typeof candidate?.token === 'string'
    ) {
      token = candidate.token;
      return true;
    }
    if (
      ['nextContinuationData', 'reloadContinuationData'].includes(key) &&
      typeof candidate?.continuation === 'string'
    ) {
      token = candidate.continuation;
      return true;
    }
    return false;
  });
  return token;
}

function durationSecondsFromRawText(value) {
  const text = rawTextValue(value) ?? value;
  if (typeof text !== 'string') return 0;
  const clock = text.match(/(?:^|\D)(\d{1,3}):(\d{2})(?::(\d{2}))?(?:\D|$)/);
  if (clock) {
    return clock[3]
      ? Number(clock[1]) * 3600 + Number(clock[2]) * 60 + Number(clock[3])
      : Number(clock[1]) * 60 + Number(clock[2]);
  }
  const hours = Number(
    text.match(/(\d+)\s*(?:hours?|hrs?|小时|小時)/i)?.[1] ?? 0,
  );
  const minutes = Number(
    text.match(/(\d+)\s*(?:minutes?|mins?|分钟|分鐘)/i)?.[1] ?? 0,
  );
  const seconds = Number(
    text.match(/(\d+)\s*(?:seconds?|secs?|秒)/i)?.[1] ?? 0,
  );
  return hours * 3600 + minutes * 60 + seconds;
}

function httpResponseError(statusCode, operation = 'YouTube request') {
  const error = new Error(
    `${operation} failed with HTTP ${statusCode ?? 'unknown'}.`,
  );
  error.statusCode = statusCode;
  return error;
}

async function executeRawBrowse(actions, request) {
  const result = await executeRawBrowseWithResolution(actions, request);
  return result.response;
}

async function executeRawBrowseWithResolution(actions, request) {
  let browseId = request.browseId;
  let response = await actions.execute('browse', {
    ...request,
    client: 'YTMUSIC',
  });
  for (let redirects = 0; redirects < 2; redirects += 1) {
    if (response?.success === false) {
      throw httpResponseError(response.status_code);
    }
    const redirect = rawBrowseRedirect(response?.data ?? response);
    if (!redirect) return { response, browseId };
    browseId = redirect.browseId;
    response = await actions.execute(redirect.endpoint, {
      browseId: redirect.browseId,
      ...(redirect.params ? { params: redirect.params } : {}),
      client: 'YTMUSIC',
    });
  }
  if (response?.success === false) {
    throw httpResponseError(response.status_code);
  }
  return { response, browseId };
}

function rawBrowseRedirect(page) {
  for (const action of listOf(page?.onResponseReceivedActions)) {
    const endpoint = action?.navigateAction?.endpoint;
    const browse = endpoint?.browseEndpoint;
    if (typeof browse?.browseId !== 'string' || !browse.browseId) continue;
    const apiUrl = endpoint?.commandMetadata?.webCommandMetadata?.apiUrl;
    return {
      endpoint:
        typeof apiUrl === 'string' && apiUrl.includes('/youtubei/v1/')
          ? apiUrl.replace('/youtubei/v1/', '')
          : 'browse',
      browseId: browse.browseId,
      params: typeof browse.params === 'string' ? browse.params : null,
    };
  }
  return null;
}

function mapPlaylistHeader(id, rawHeader, background) {
  const header = rawHeader?.header ?? rawHeader;
  return {
    id,
    title: textValue(header?.title) || 'Playlist',
    owner: nullableMetadataText(
      header?.author?.name ?? header?.strapline_text_one,
    ),
    itemCount: nullableMetadataText(
      header?.song_count ?? header?.total_items ?? header?.second_subtitle,
    ),
    description: nullableMetadataText(header?.description),
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

function normalizeArtworkUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value.trim());
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : null;
  } catch {
    return null;
  }
}

function imageExtension(contentType, url) {
  const normalizedType = String(contentType ?? '')
    .split(';', 1)[0]
    .trim()
    .toLowerCase();
  if (normalizedType === 'image/png') return 'png';
  if (normalizedType === 'image/webp') return 'webp';
  if (normalizedType === 'image/avif') return 'avif';
  if (['image/jpeg', 'image/jpg'].includes(normalizedType)) return 'jpg';
  try {
    const extension = path.extname(new URL(url).pathname)
      .slice(1)
      .toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp', 'avif'].includes(extension)) {
      return extension === 'jpeg' ? 'jpg' : extension;
    }
  } catch {
    // A validated URL can still have no pathname extension.
  }
  return 'jpg';
}

function encodeLrc(lines) {
  const encoded = listOf(lines)
    .map((line) => {
      const text = String(line?.text ?? '').replace(/\s*\r?\n\s*/g, ' ').trim();
      if (!text) return null;
      if (!Number.isFinite(line?.startSeconds) || line.startSeconds < 0) {
        return text;
      }
      const hundredths = Math.round(line.startSeconds * 100);
      const minutes = Math.floor(hundredths / 6000);
      const seconds = ((hundredths % 6000) / 100)
        .toFixed(2)
        .padStart(5, '0');
      return `[${String(minutes).padStart(2, '0')}:${seconds}]${text}`;
    })
    .filter(Boolean);
  return encoded.length ? `${encoded.join('\n')}\n` : '';
}

function stringMetadata(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
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

function nullableMetadataText(value) {
  const text = textValue(value);
  if (!text || text.toLowerCase() === 'n/a') {
    return null;
  }
  return text;
}

function metadataText(metadata) {
  if (!metadata) return null;
  const rows = metadata.metadata_rows ?? metadata.rows ?? [];
  return textValue(rows[0]?.metadata_parts?.[0]?.text);
}

function artistsFromSubtitle(subtitle) {
  if (typeof subtitle !== 'string') return [];
  const parts = subtitle
    .split(' • ')
    .map((part) => nullableMetadataText(part.trim()))
    .filter(Boolean);
  return parts.length > 1 ? parts.slice(1) : [];
}

function albumFromSubtitle(subtitle) {
  if (typeof subtitle !== 'string') return null;
  const parts = subtitle
    .split(' • ')
    .map((part) => nullableMetadataText(part.trim()))
    .filter(Boolean);
  return parts.length > 1 ? parts[0] ?? null : null;
}

export function mapAccountProfile(accountInfo) {
  const accounts = Array.isArray(accountInfo)
    ? accountInfo
    : arrayOf(accountInfo?.contents?.contents);
  const account =
    accounts.find((item) => item?.is_selected && item?.account_name) ??
    accounts.find((item) => item?.account_name);
  if (!account) return null;
  const displayName = textValue(account.account_name);
  const avatarUrl = largestThumbnail(arrayOf(account.account_photo))?.url ?? null;
  return displayName || avatarUrl ? { displayName: displayName ?? null, avatarUrl } : null;
}

function selectAdaptivePlaybackFormats(info) {
  const formats = arrayOf(info?.streaming_data?.adaptive_formats);
  const videoFormats = formats.filter(
    (format) => format?.has_video && !format?.has_audio,
  );
  let audioFormats = formats.filter(
    (format) => format?.has_audio && !format?.has_video && !format?.has_text,
  );
  if (videoFormats.length === 0 || audioFormats.length === 0) return null;

  const hdFormats = videoFormats.filter((format) => {
    const height = Number(format?.height ?? 0);
    return height > 0 && height <= 1080;
  });
  const videoPool = hdFormats.length > 0 ? hdFormats : videoFormats;
  videoPool.sort((left, right) => {
    const heightDifference =
      Number(right?.height ?? 0) - Number(left?.height ?? 0);
    if (heightDifference !== 0) return heightDifference;
    const codecDifference =
      Number(String(right?.mime_type ?? '').includes('avc')) -
      Number(String(left?.mime_type ?? '').includes('avc'));
    return codecDifference !== 0
      ? codecDifference
      : Number(right?.bitrate ?? 0) - Number(left?.bitrate ?? 0);
  });

  const originalAudio = audioFormats.filter((format) => format?.is_original);
  if (originalAudio.length > 0) audioFormats = originalAudio;
  const unprocessedAudio = audioFormats.filter((format) => !format?.is_drc);
  if (unprocessedAudio.length > 0) audioFormats = unprocessedAudio;
  audioFormats.sort(
    (left, right) =>
      Number(right?.bitrate ?? 0) - Number(left?.bitrate ?? 0),
  );
  return { video: videoPool[0], audio: audioFormats[0] };
}

function normalizeFeedItemType(value) {
  if (typeof value !== 'string') return null;
  const type = value
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_')
    .replace(/^music_/, '');
  if (type === 'podcast_show') return 'podcast';
  return [
    'album',
    'artist',
    'channel',
    'category',
    'episode',
    'non_music_track',
    'playlist',
    'podcast',
    'song',
    'subscriber',
    'video',
  ].includes(type)
    ? type
    : null;
}

function isTrackItemType(itemType) {
  return ['episode', 'song', 'video', 'non_music_track'].includes(itemType);
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
  if (browseId.startsWith('MPSP')) return 'podcast';
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

function appendUniqueTracks(target, pageTracks, seenVideoIds) {
  let appended = false;
  for (const track of pageTracks) {
    if (seenVideoIds.has(track.videoId)) continue;
    seenVideoIds.add(track.videoId);
    target.push(track);
    appended = true;
  }
  return appended;
}

function isContinuationExhausted(error) {
  return /continuation did not have any content|continuation not found/i.test(
    error?.message ?? '',
  );
}

function feedFailure(code, message, diagnosticStage, error) {
  return new SidecarError(code, message, {
    diagnosticStage,
    ...describeUpstreamError(error),
  });
}

function authenticationFailure(error, diagnosticStage) {
  const details = {
    diagnosticStage,
    ...describeUpstreamError(error),
  };
  if (details.statusCode === 401 || details.statusCode === 403) {
    return new SidecarError(
      'INVALID_COOKIE',
      'The YouTube Cookie header is invalid or expired.',
      details,
    );
  }
  if (isNetworkFailure(error, details.upstreamCode)) {
    return new SidecarError(
      'AUTHENTICATION_UNAVAILABLE',
      'YouTube could not be reached to verify this Cookie.',
      details,
    );
  }
  return new SidecarError(
    'AUTHENTICATION_FAILED',
    'YouTube Cookie authentication could not be verified.',
    details,
  );
}

function isNetworkFailure(error, upstreamCode) {
  if (
    [
      'ECONNREFUSED',
      'ECONNRESET',
      'ENETUNREACH',
      'ENOTFOUND',
      'ETIMEDOUT',
      'UND_ERR_CONNECT_TIMEOUT',
      'UND_ERR_HEADERS_TIMEOUT',
      'UND_ERR_SOCKET',
    ].includes(upstreamCode)
  ) {
    return true;
  }
  return /fetch failed|network|socket|timed?\s*out/i.test(error?.message ?? '');
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
    statusCodeFromInfo(error?.info),
    statusCodeFromMessage(error?.message),
  );
  const upstreamCode =
    safeDiagnosticValue(details?.upstreamCode) ??
    (isSidecarError ? null : safeDiagnosticValue(error?.code)) ??
    safeDiagnosticValue(error?.cause?.code);
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

function statusCodeFromInfo(info) {
  if (typeof info === 'string') {
    try {
      return statusCodeFromInfo(JSON.parse(info));
    } catch {
      return null;
    }
  }
  return firstStatusCode(
    info?.statusCode,
    info?.status_code,
    info?.error?.code,
  );
}

function statusCodeFromMessage(message) {
  if (typeof message !== 'string') return null;
  const match = message.match(/status(?:\s+code)?\s+(\d{3})/i);
  return match ? Number.parseInt(match[1], 10) : null;
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

function normalizeCookieHeader(value) {
  if (typeof value !== 'string') return '';
  const trimmed = value.trim();
  const headerLine = trimmed
    .split(/\r?\n/)
    .find((line) => /^cookie\s*:/i.test(line));
  return (headerLine ?? trimmed).replace(/^cookie\s*:\s*/i, '').trim();
}
