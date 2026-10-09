import {initAsyncCompiler} from 'sass-embedded';
import postcss from 'postcss';
import prefixProperties from 'postcss-prefix-custom-properties';
import autoprefixer from 'autoprefixer';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

export async function createCompiler() {
  const sass = await initAsyncCompiler();
  const browsers = (await readFile(new URL('./node_modules/bootstrap/.browserslistrc',import.meta.url),'utf8'))
    .split('\n').map(line=>line.trim()).filter(line=>line && !line.startsWith('#'));
  const processor = postcss([
    prefixProperties({prefix:'bs-',ignore:[/^--bs-/,/^--bd-/]}),
    autoprefixer({cascade:false,overrideBrowserslist:browsers}),
    {postcssPlugin:'remove-redundant-prefixes',OnceExit(root) {
      root.walkDecls(decl=> { if (['-webkit-transition','-moz-transition'].includes(decl.prop)) decl.remove(); });
    }}
  ]);
  return {
    async compile() {
      const source = await readFile(new URL('./live.scss', import.meta.url), 'utf8');
      const result = await sass.compileStringAsync(source,{
        loadPaths:[fileURLToPath(new URL('./node_modules/',import.meta.url))],
        style:'compressed',sourceMap:false
      });
      return (await processor.process(result.css,{from:undefined,map:false})).css;
    },
    dispose:()=>sass.dispose()
  };
}
