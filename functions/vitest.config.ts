import { defineConfig } from 'vitest/config';

// Exclude the tsc build output (functions/lib/, gitignored) from test
// discovery. Without this, running `npm run build` before `npm test` in the
// same session leaves compiled *.test.js files under lib/ that vitest's
// default include glob also matches — and vitest refuses to require() a
// CommonJS-compiled copy of itself, crashing the whole run. Source tests
// under src/ and test/ are unaffected.
export default defineConfig({
  test: {
    exclude: ['lib/**', 'node_modules/**'],
  },
});
