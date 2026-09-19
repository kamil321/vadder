import { promises as fs } from 'node:fs';
import { createWriteStream } from 'node:fs';
import * as path from 'node:path';
import archiver from 'archiver';
import chokidar, { FSWatcher } from 'chokidar';
import { Config } from './config.js';
import { sha256File } from './hash.js';

export type IgnoreFn = (rel: string) => boolean;

/** Default excludes for the mods profile: logs, the BepInEx runtime cache, and the marker. */
export function defaultModsIgnore(): IgnoreFn[] {
  return [
    (rel) => rel === 'VADDER_WRITABLE',
    (rel) => rel.toLowerCase().endsWith('.log'),
    (rel) => {
      const r = rel.toLowerCase();
      return r === 'bepinex/cache' || r.startsWith('bepinex/cache/');
    },
  ];
}

export interface Artifact {
  name: string;
  sourceDir: string;
  ignore: IgnoreFn[];
  inject?: { name: string; content: string }[];
}

async function walk(dir: string, base: string): Promise<string[]> {
  const out: string[] = [];
  await walkRec(dir, base, out);
  return out;
}

async function walkRec(dir: string, base: string, out: string[]): Promise<void> {
  let entries;
  try {
    entries = (await fs.readdir(dir, { withFileTypes: true })).sort((a, b) =>
      a.name.localeCompare(b.name),
    );
  } catch {
    return;
  }
  for (const entry of entries) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await walkRec(abs, base, out);
    } else if (entry.isFile()) {
      out.push(abs);
    }
  }
}

export async function packArtifact(
  artifact: Artifact,
  zipPath: string,
  log: (msg: string) => void,
): Promise<boolean> {
  const tmpZip = `${zipPath}.tmp`;
  const zipDir = path.dirname(zipPath);
  let sourceExists = false;
  try {
    await fs.access(artifact.sourceDir);
    sourceExists = true;
  } catch {
    /* handled below */
  }
  if (!sourceExists) {
    log(`source "${artifact.sourceDir}" is missing; zip not rebuilt`);
    return false;
  }

  const files = await walk(artifact.sourceDir, artifact.sourceDir);
  const packed: string[] = [];
  const archive = archiver('zip', { zlib: { level: 6 } });

  try {
    await fs.mkdir(zipDir, { recursive: true });
    await new Promise<void>((resolve, reject) => {
      const output = createWriteStream(tmpZip);
      archive.on('error', reject);
      output.on('error', reject);
      output.on('close', resolve);
      archive.pipe(output);

      for (const file of files) {
        const rel = path.relative(artifact.sourceDir, file).split(path.sep).join('/');
        if (artifact.ignore.some((fn) => fn(rel))) continue;
        archive.file(file, { name: rel });
        packed.push(rel);
      }
      for (const inj of artifact.inject ?? []) {
        archive.append(inj.content, { name: inj.name });
        packed.push(inj.name);
      }

      void archive.finalize();
    });

    await fs.rename(tmpZip, zipPath);
    log(`${artifact.name}.zip rebuilt: ${packed.length} file(s) packed`);
    return true;
  } catch (err) {
    log(`failed to build ${artifact.name}.zip: ${(err as Error).message}`);
    try {
      await fs.unlink(tmpZip);
    } catch {
      /* ignore */
    }
    return false;
  }
}

export class Packer {
  private readonly artifacts: Record<string, Artifact> = {};
  private readonly hashes = new Map<string, string>();
  private readonly built = new Map<string, string>();
  private readonly timers = new Map<string, NodeJS.Timeout>();
  private watcher?: FSWatcher;

  constructor(private readonly config: Config, private readonly log: (msg: string) => void = console.log) {
    if (config.modsDir) {
      this.artifacts.mods = {
        name: 'mods',
        sourceDir: config.modsDir,
        ignore: defaultModsIgnore(),
        inject: [{ name: 'VADDER_WRITABLE', content: '' }],
      };
    }
    this.artifacts.scripts = {
      name: 'scripts',
      sourceDir: config.scriptsDir,
      ignore: [],
    };
  }

  names(): string[] {
    return Object.keys(this.artifacts);
  }

  hash(name: string): string | null {
    return this.hashes.get(name) ?? null;
  }

  zipName(name: string): string {
    return `${name}.zip`;
  }

  zipPath(name: string): string | null {
    return this.built.get(name) ?? null;
  }

  async start(): Promise<void> {
    for (const name of this.names()) {
      await this.build(name);
    }

    await this.checkServerSourceMarker();

    const watchDirs: string[] = [];
    for (const name of this.names()) {
      const artifact = this.artifacts[name];
      try {
        await fs.access(artifact.sourceDir);
        watchDirs.push(artifact.sourceDir);
      } catch {
        this.log(`warning: "${artifact.sourceDir}" does not exist; not watching ${name}`);
      }
    }
    if (watchDirs.length === 0) return;

    this.watcher = chokidar.watch(watchDirs, { ignoreInitial: true });
    this.watcher.on('all', (_event, filePath) => this.onFsChange(filePath));
    this.log(`watching: ${watchDirs.join(', ')}`);
  }

  async stop(): Promise<void> {
    for (const timer of this.timers.values()) clearTimeout(timer);
    this.timers.clear();
    await this.watcher?.close();
  }

  private async checkServerSourceMarker(): Promise<void> {
    if (!this.config.modsDir) return;
    try {
      await fs.access(path.join(this.config.modsDir, 'VADDER_WRITABLE'));
      this.log(
        'warning: VADDER_WRITABLE was found inside the server profile source. ' +
          'Clients would no longer be able to tell this machine is the server. Remove that file.',
      );
    } catch {
      /* good: marker not present in the server source */
    }
  }

  private whichArtifact(filePath: string): string | null {
    const normalized = path.normalize(filePath);
    for (const name of this.names()) {
      const dir = this.artifacts[name].sourceDir;
      const check = path.relative(dir, normalized);
      if (check !== '' && !check.startsWith('..') && !path.isAbsolute(check)) return name;
    }
    return null;
  }

  private onFsChange(filePath: string): void {
    const name = this.whichArtifact(filePath);
    if (!name) return;
    if (name === 'mods') {
      const marker = path.join(this.config.modsDir ?? '', 'VADDER_WRITABLE');
      if (path.normalize(filePath).toLowerCase() === marker.toLowerCase()) {
        this.log('warning: VADDER_WRITABLE appeared in the server source profile.');
      }
    }
    if (this.timers.has(name)) return;
    this.log(`${name}: change detected, rebuilding once quiet for ${this.config.debounceMs} ms`);
    const timer = setTimeout(() => {
      this.timers.delete(name);
      void this.build(name);
    }, this.config.debounceMs);
    this.timers.set(name, timer);
  }

  async build(name: string): Promise<void> {
    const artifact = this.artifacts[name];
    if (!artifact) return;
    const zipPath = path.join(this.config.dataDir, `${name}.zip`);
    const ok = await packArtifact(artifact, zipPath, (msg) => this.log(`[${name}] ${msg}`));
    if (!ok) return;
    const hash = await sha256File(zipPath);
    this.hashes.set(name, hash);
    this.built.set(name, zipPath);
    this.log(`[${name}] hash: ${hash}`);
  }
}