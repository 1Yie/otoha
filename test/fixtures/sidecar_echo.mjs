import { createInterface } from 'node:readline';

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });

lines.on('line', (line) => {
  const request = JSON.parse(line);
  if (request.method === 'partial') {
    process.stdout.write(
      `${JSON.stringify({
        event: 'library.section_unavailable',
        data: {
          method: 'library.media',
          code: 'LIBRARY_SECTION_UNAVAILABLE',
          errorType: 'Error',
          diagnosticStage: 'library.filter.albums',
        },
      })}\n`,
    );
    process.stdout.write(
      `${JSON.stringify({
        id: request.id,
        ok: true,
        result: { partial: true },
      })}\n`,
    );
    return;
  }
  if (request.method === 'fail') {
    process.stdout.write(
      `${JSON.stringify({
        event: 'request.failure',
        data: {
          method: 'feed.home',
          code: 'YOUTUBE_ERROR',
          errorType: 'InnertubeError',
          diagnosticStage: 'browse.request',
          statusCode: 403,
        },
      })}\n`,
    );
    process.stdout.write(
      `${JSON.stringify({
        id: request.id,
        ok: false,
        error: {
          code: 'YOUTUBE_ERROR',
          message: 'The YouTube service could not complete this request.',
          details: {
            errorType: 'InnertubeError',
            diagnosticStage: 'browse.request',
            statusCode: 403,
          },
        },
      })}\n`,
    );
    return;
  }
  process.stdout.write(
    `${JSON.stringify({ id: request.id, ok: true, result: { pid: process.pid } })}\n`,
  );
});

lines.on('close', () => process.exit(0));
