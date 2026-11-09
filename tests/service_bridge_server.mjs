import {resolve, dirname, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {access} from 'node:fs/promises';
import {createApp} from '../server/src/index.js';
import {DeepSeekProvider} from '../server/src/provider.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dataDir = resolve(process.argv[2] || '');
if (dirname(dataDir) !== resolve(root, '.runtime') || !/^test-bridge-[0-9a-f-]+$/.test(basename(dataDir))) throw new Error('An isolated .runtime/test-bridge-UUID directory is required.');
// Deliberately no dotenv and no inherited API key, model, token, or production port.
const app = await createApp({host: '127.0.0.1', port: 18787, token: '', dataDir, provider: new DeepSeekProvider({apiKey: ''})});
await app.listen();
console.log('BRIDGE_SERVER_READY port=18787 configured=false');
let closed = false;
const close = async () => { if (closed) return; closed = true; clearInterval(timer); await app.close(); process.exit(0); };
const timer = setInterval(async () => { try { await access(resolve(dataDir, 'stop.request')); await close(); } catch { /* Wait for runner shutdown signal. */ } }, 100);
process.on('SIGINT', close); process.on('SIGTERM', close);
