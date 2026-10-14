#!/usr/bin/env node
// Generate the inspector's class list from the exact Bootstrap CSS Foundry ships.
// Requires the sibling Bootstrap checkout's npm dependencies for CSS parsing.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const bootstrap = path.resolve(root, "../bootstrap");
const requireBootstrap = createRequire(path.join(bootstrap, "package.json"));
const postcss = requireBootstrap("postcss");
const selectorParser = requireBootstrap("postcss-selector-parser");
const resourceDirectory = path.join(root, "Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources");
const stylesheets = fs.readdirSync(resourceDirectory)
  .filter(name => /^bootstrap-[^-]+(?:-[^-]+)*\.min\.css$/.test(name) && !name.includes("-foundry."));

if (stylesheets.length !== 1) {
  throw new Error("Expected exactly one bundled official Bootstrap stylesheet.");
}

const stylesheet = stylesheets[0];
const css = fs.readFileSync(path.join(resourceDirectory, stylesheet), "utf8");
const classes = new Map();
const rootNode = postcss.parse(css, { from: stylesheet });

rootNode.walkRules(rule => {
  let ancestor = rule.parent;
  let layer = "unlayered";
  while (ancestor) {
    if (ancestor.type === "atrule" && ancestor.name === "layer") {
      layer = ancestor.params;
      break;
    }
    ancestor = ancestor.parent;
  }

  selectorParser(selectors => {
    selectors.walkClasses(node => {
      const name = node.value;
      if (!classes.has(name)) classes.set(name, new Set());
      classes.get(name).add(layer);
    });
  }).processSync(rule.selector);
});

const output = {
  stylesheet,
  classes: [...classes.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, layers]) => ({ name, layers: [...layers].sort() }))
};
const destination = path.join(resourceDirectory, "bootstrap-class-catalog.json");
fs.writeFileSync(destination, JSON.stringify(output));
console.log(`Wrote ${output.classes.length} classes from ${stylesheet} to ${destination}`);
