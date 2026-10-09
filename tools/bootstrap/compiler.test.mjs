import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createCompiler} from './compiler.mjs';

test('live build retains native classes with variable-driven spacing and containers', async () => {
  const compiler = await createCompiler();
  try {
    const css = await compiler.compile();
    assert.match(css, /\.p-5\{padding:var\(--bs-spacer\)/);
    assert.match(css, /\.gap-5\{gap:var\(--bs-spacer\)/);
    assert.match(css, /margin-block-end:var\(--bs-spacer\)/);
    assert.match(css, /max-width:var\(--bs-container-xl,\s*1200px\)/);
    assert.match(css, /md\\:p-5/);
    assert.doesNotMatch(css, /--spacer\b/);
  } finally { await compiler.dispose(); }
});
