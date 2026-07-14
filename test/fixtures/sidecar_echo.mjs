import { createInterface } from 'node:readline';

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });

lines.on('line', (line) => {
  const request = JSON.parse(line);
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
