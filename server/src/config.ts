import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

export interface Config {
  port: number;
  host: string;
  modsDir: string | null;
  scriptsDir: string;
  dataDir: string;
  debounceMs: number;
}

function str(v: string | undefined, def: string): string {
  return v !== undefined && v.trim() !== '' ? v.trim() : def;
}

function int(v: string | undefined, def: number): number {
  const n = Number.parseInt(v ?? '', 10);
  return Number.isFinite(n) ? n : def;
}

export function loadConfig(): Config {
  const thisFile = fileURLToPath(import.meta.url);
  const here = path.dirname(thisFile); // server/src or server/dist
  const projectRoot = path.dirname(here); // server/
  const env = process.env;

  let modsDir: string | null = null;
  if (env.VADDER_MODS_DIR && env.VADDER_MODS_DIR.trim() !== '') {
    modsDir = env.VADDER_MODS_DIR;
  } else if (env.APPDATA) {
    modsDir = path.join(env.APPDATA, 'r2modmanPlus-local', 'Valheim', 'profiles', 'valheim_vadder_sync');
  } else {
    console.warn('[vadder] no VADDER_MODS_DIR and no APPDATA set; mods artifact is disabled');
  }

  return {
    port: int(env.VADDER_PORT, 2460),
    host: str(env.VADDER_HOST, '0.0.0.0'),
    modsDir,
    scriptsDir: path.resolve(str(env.VADDER_SCRIPTS_DIR, path.join(projectRoot, 'client-scripts'))),
    dataDir: path.resolve(str(env.VADDER_DATA_DIR, path.join(projectRoot, 'data'))),
    debounceMs: Math.max(0, int(env.VADDER_DEBOUNCE_MS, 30_000)),
  };
}