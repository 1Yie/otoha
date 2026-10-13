// Reports the session cache directory the host passed through the environment.
import { createInterface } from 'node:readline';

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });

lines.on('line', (line) => {
  const request = JSON.parse(line);
  process.stdout.write(
    `${JSON.stringify({
      id: request.id,
      ok: true,
      result: { cacheDir: process.env.OTOHA_SIDECAR_CACHE_DIR ?? null },
    })}\n`,
  );
});
