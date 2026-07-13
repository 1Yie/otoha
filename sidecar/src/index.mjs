import { createInterface } from 'node:readline';

import { serializeError, YouTubeService } from './youtube_service.mjs';

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const service = new YouTubeService({
  emit: (event, data) => write({ event, data }),
});

const methods = {
  'session.restore': ({ credential } = {}) => service.restore(credential),
  'session.status': () => service.status(),
  'auth.cookie.signIn': ({ cookie } = {}) => service.signInWithCookie(cookie),
  'auth.signOut': () => service.signOut(),
  'library.playlists': () => service.getLibraryPlaylists(),
  'library.playlist': ({ playlistId } = {}) => service.getPlaylist(playlistId),
  'feed.home': () => service.getHomeFeed(),
  'feed.explore': () => service.getExploreFeed(),
  'search.music': ({ query } = {}) => service.searchMusic(query),
  'search.music': ({ query } = {}) => service.searchMusic(query),
  'feed.collection': ({ itemType, id } = {}) =>
    service.getFeedCollection(itemType, id),
  'feed.track': ({ videoId } = {}) => service.getFeedTrack(videoId),
  'feed.browse': ({ itemType, id, browseParams } = {}) =>
    service.getFeedBrowse(itemType, id, browseParams),
};

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
let inputClosed = false;
let activeRequests = 0;

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
    const result = await handler(request.params);
    write({ id: request.id, ok: true, result });
  } catch (error) {
    write({ id: request?.id ?? null, ok: false, error: serializeError(error) });
  } finally {
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
