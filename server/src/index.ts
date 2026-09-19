import express from 'express';
import type { Request, Response } from 'express';
import { loadConfig } from './config.js';
import { Packer } from './pack.js';

const config = loadConfig();
const packer = new Packer(config);

const app = express();
app.disable('x-powered-by');

function serveHash(name: string) {
  return (_req: Request, res: Response): void => {
    const hash = packer.hash(name);
    res.status(hash ? 200 : 404).type('text/plain').set('Cache-Control', 'no-store');
    res.send(hash ?? `${name}.zip not built yet`);
  };
}

function serveZip(name: string) {
  return (_req: Request, res: Response): void => {
    const zipPath = packer.zipPath(name);
    if (!zipPath) {
      res.status(404).type('text/plain').send(`${name}.zip not available`);
      return;
    }
    res.set('Cache-Control', 'no-store, must-revalidate');
    res.download(zipPath, `${name}.zip`);
  };
}

app.get('/api/mods/hash', serveHash('mods'));
app.get('/api/mods/zip', serveZip('mods'));
app.get('/api/scripts/hash', serveHash('scripts'));
app.get('/api/scripts/zip', serveZip('scripts'));

app.get('/api/health', (_req, res) => {
  res.status(200).json({
    ok: true,
    mods: packer.hash('mods') !== null,
    scripts: packer.hash('scripts') !== null,
    modsDir: config.modsDir,
    scriptsDir: config.scriptsDir,
    dataDir: config.dataDir,
    debounceMs: config.debounceMs,
  });
});

app.get('/', (_req, res) => {
  res.type('text/plain').send(
    [
      'vadder server running',
      '',
      '  GET /api/mods/hash      -> sha256 hex of mods.zip',
      '  GET /api/mods/zip       -> download mods.zip',
      '  GET /api/scripts/hash   -> sha256 hex of scripts.zip',
      '  GET /api/scripts/zip    -> download scripts.zip',
      '  GET /api/health         -> json status',
      '',
    ].join('\n'),
  );
});

async function main(): Promise<void> {
  await packer.start();
  app.listen(config.port, config.host, () => {
    console.log(`[vadder] listening on http://${config.host}:${config.port}`);
  });
}

main().catch((err) => {
  console.error('[vadder] fatal:', err);
  process.exit(1);
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    void packer.stop().then(() => process.exit(0));
  });
}