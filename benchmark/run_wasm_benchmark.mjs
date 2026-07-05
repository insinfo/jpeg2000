import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [loaderPath, wasmPath, ...dartArgs] = process.argv.slice(2);

if (!loaderPath || !wasmPath) {
  console.error(
    'Usage: node benchmark/run_wasm_benchmark.mjs <loader.mjs> <module.wasm> [dart args...]',
  );
  process.exit(64);
}

const { compile } = await import(pathToFileURL(resolve(loaderPath)));
const bytes = await readFile(resolve(wasmPath));
const app = await compile(bytes);
const instance = await app.instantiate({});

instance.invokeMain(...dartArgs);
