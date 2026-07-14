import { createInterface } from 'node:readline';

import { serializeError, YouTubeService } from './youtube_service.mjs';

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const service = new YouTubeService({
  emit: (event, data) => write({ event, data }),
});

const methods = {
  'session.restore': ({ credential, locale } = {}) =>
    service.restore(credential, locale),
  'session.status': () => service.status(),
  'session.setLocale': ({ locale } = {}) => service.setLocale(locale),
  'auth.cookie.signIn': ({ cookie, locale } = {}) =>
    service.signInWithCookie(cookie, locale),
  'auth.signOut': () => service.signOut(),
  'library.playlists': () => service.getLibraryPlaylists(),
  'library.playlist': ({ playlistId } = {}) => service.getPlaylist(playlistId),
  'history.get': () => service.getHistory(),
  'feed.home': () => service.getHomeFeed(),
  'feed.home.more': () => service.getMoreHomeFeed(),
  'feed.explore': () => service.getExploreFeed(),
  'feed.explore.more': () => service.getMoreExploreFeed(),
  'interaction.rate': ({ videoId, rating } = {}) =>
    service.rateVideo(videoId, rating),
  'comments.get': ({ videoId } = {}) => service.getComments(videoId),
  'comments.create': ({ videoId, text } = {}) =>
    service.createComment(videoId, text),
  'search.music': ({ query } = {}) => service.searchMusic(query),
  'feed.collection': ({ itemType, id } = {}) =>
    service.getFeedCollection(itemType, id),
  'feed.track': ({ videoId } = {}) => service.getFeedTrack(videoId),
  'playback.resolve': ({ videoId } = {}) => service.getPlaybackStream(videoId),
  'download.track': ({ videoId, directory } = {}) => service.downloadAudio(videoId, directory),
  'lyrics.get': ({ videoId, title, artist, album, durationSeconds } = {}) =>
    service.getLyrics(videoId, { title, artist, album, durationSeconds }),
  'feed.browse': ({ itemType, id, browseParams } = {}) =>
    service.getFeedBrowse(itemType, id, browseParams),
};

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
let inputClosed = false;
let activeRequests = 0;
const activeRequestMethods = new Map();

lines.on('line', async (line) => {
  activeRequests += 1;
  let request;
  try {
    request = JSON.parse(line);
    const handler = methods[request.method];
    if (!request.id || !handler) {
      throw Object.assign(new Error('Unknown or malformed sidecar request.'), {
        code: 'INVALID_REQUEST',
      });
    }
    activeRequestMethods.set(request.id, request.method);
    const result = await handler(request.params);
    write({ id: request.id, ok: true, result });
  } catch (error) {
    const serialized = serializeError(error);
    write({
      event: 'request.failure',
      data: {
        method: request?.method ?? 'unknown',
        code: serialized.code,
        ...serialized.details,
      },
    });
    write({ id: request?.id ?? null, ok: false, error: serialized });
  } finally {
    if (request?.id) {
      activeRequestMethods.delete(request.id);
    }
    activeRequests -= 1;
    exitAfterInputCloses();
  }
});

lines.on('close', () => {
  inputClosed = true;
  exitAfterInputCloses();
  if (activeRequests > 0) {
    setTimeout(() => process.exit(0), 5000);
  }
});

function exitAfterInputCloses() {
  if (inputClosed && activeRequests === 0) {
    process.exit(0);
  }
}

process.on('SIGTERM', () => process.exit(0));
process.on('uncaughtException', reportCrash);
process.on('unhandledRejection', reportUnhandledRejection);

let isCrashing = false;

function reportCrash(error) {
  if (isCrashing) return;
  isCrashing = true;
  const serialized = serializeError(error);
  const message = JSON.stringify({
    event: 'sidecar.crash',
    data: {
      method: activeRequestMethod(),
      code: serialized.code,
      ...serialized.details,
    },
  });
  let exited = false;
  const exit = () => {
    if (exited) return;
    exited = true;
    process.exit(1);
  };
  try {
    process.stdout.write(`${message}\n`, exit);
    setTimeout(exit, 100).unref();
  } catch {
    exit();
  }
}

function reportUnhandledRejection(error) {
  const serialized = serializeError(error);
  write({
    event: 'sidecar.unhandled_rejection',
    data: {
      method: activeRequestMethod(),
      code: serialized.code,
      ...serialized.details,
    },
  });
}

function activeRequestMethod() {
  return [...activeRequestMethods.values()].at(-1) ?? 'sidecar.process';
}
