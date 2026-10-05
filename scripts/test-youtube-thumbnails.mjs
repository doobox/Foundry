import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const swift = readFileSync(new URL('../Foundry/Renderer/CanvasYouTubeThumbnails.swift', import.meta.url), 'utf8');
const script = swift.split('#"""')[1].split('"""#')[0];
function setup(width, complete = true) {
    const listeners = {};
    const labels = [];
    const image = { dataset: { foundryYoutubeThumbnail: 'M7lc1UVf-VE' }, style: {}, naturalWidth: width, complete,
        addEventListener: (name, callback) => { listeners[name] = callback; }, parentElement: { append: label => labels.push(label) } };
    let scan;
    vm.runInNewContext(script, {
        document: { querySelectorAll: () => [image], documentElement: {}, createElement: () => ({style:{}}) },
        MutationObserver: class { constructor(callback) { scan = callback; } observe() {} }
    });
    return { image, listeners, labels, scan };
}
test('keeps a successful high resolution thumbnail', () => {
    const { image, listeners, scan } = setup(1280);
    listeners.load(); scan();
    assert.equal(image.src, undefined);
});
test('falls back for failed loads and tiny unavailable placeholders', () => {
    const { image, listeners, labels } = setup(120);
    assert.ok(image.src.endsWith('/sddefault.jpg'));
    listeners.error();
    assert.ok(image.src.endsWith('/hqdefault.jpg'));
    listeners.load();
    assert.ok(image.src.endsWith('/mqdefault.jpg'));
    listeners.error();
    assert.equal(image.style.visibility, 'hidden');
    assert.equal(labels.length, 1);
    assert.equal(labels[0].textContent, 'YouTube thumbnail unavailable');
});
test('waits for pending images and avoids duplicate listeners', () => {
    const { image, listeners, scan } = setup(0, false);
    assert.equal(image.src, undefined);
    scan(); listeners.error();
    assert.ok(image.src.endsWith('/sddefault.jpg'));
    image.naturalWidth = 640;
    listeners.load();
    assert.ok(image.src.endsWith('/sddefault.jpg'));
});
