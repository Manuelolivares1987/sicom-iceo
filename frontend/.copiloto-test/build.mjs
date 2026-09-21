import { build } from 'esbuild'
import { resolve } from 'node:path'
const T = resolve('.copiloto-test')
await build({
  entryPoints: [`${T}/harness.ts`], bundle: true, platform: 'node', format: 'esm', outfile: `${T}/harness.mjs`,
  external: ['@anthropic-ai/sdk', '@supabase/supabase-js'], logLevel: 'warning',
  plugins: [{ name: 'alias', setup(b) {
    b.onResolve({ filter: /^@\/lib\/copiloto\/server$/ }, () => ({ path: `${T}/server-fake.ts` }))
    b.onResolve({ filter: /^next\/server$/ }, () => ({ path: `${T}/next-server.ts` }))
    b.onResolve({ filter: /^@\// }, (a) => b.resolve('./' + a.path.slice(2), { resolveDir: resolve('src'), kind: a.kind }))
  } }],
})
console.log('BUILD_OK')
