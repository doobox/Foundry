import {writeFile} from 'node:fs/promises';
import {createCompiler} from './compiler.mjs';
const compiler = await createCompiler();
try {
  const css = await compiler.compile();
  await writeFile(new URL('../../Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/bootstrap-6.0.0-alpha.1-live.min.css', import.meta.url), css);
  console.log('Built Bootstrap with runtime spacing and container tokens.');
} finally { await compiler.dispose(); }
