import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
const swift = readFileSync(new URL('../Foundry/Renderer/YouTubePosterPlayback.swift', import.meta.url), 'utf8');
const source = swift.split('#"""')[1].split('"""#')[0];
test('creates player only on activation and requests playback when ready', async () => {
    let click, player, replacement, events, playCalls = 0;
    const context = vm.createContext({ URL, location: {origin:'http://localhost:8080'}, YT: {Player: class {
        constructor(iframe, options) { assert.equal(iframe, player); events = options.events; }
    }}, document: {
        addEventListener: (name, handler) => { assert.equal(name, 'click'); click = handler; },
        createElement: tag => { assert.equal(tag, 'iframe'); player = {style:{}, dataset:{}, isConnected:true, focus() { this.focused = true; }}; return player; }
    }});
    vm.runInContext(source, context);
    assert.equal(player, undefined);
    const button = { dataset: { foundryYoutubePlay: 'https://www.youtube-nocookie.com/embed/M7lc1UVf-VE?start=42&loop=1&playlist=M7lc1UVf-VE' }, replaceWith: value => { replacement = value; } };
    click({target:{closest: () => button}});
    assert.equal(replacement, player);
    assert.equal(new URL(player.src).searchParams.get('autoplay'), '1');
    assert.equal(new URL(player.src).searchParams.get('start'), '42');
    assert.equal(player.focused, true);
    assert.equal(new URL(player.src).searchParams.get('enablejsapi'), '1');
    assert.equal(new URL(player.src).searchParams.get('origin'), 'http://localhost:8080');
    await Promise.resolve();
    events.onReady({target:{playVideo: () => playCalls++}});
    assert.equal(playCalls, 1);
    events.onAutoplayBlocked();
    assert.equal(player.dataset.foundryPlaybackBlocked, 'true');
    assert.equal(playCalls, 1);
    const originalClick = click;
    vm.runInContext(source, context);
    assert.equal(click, originalClick);
});
test('loads the API only after a click and ignores players removed before it is ready', async () => {
    let click, apiScript, iframe, constructed = 0;
    const context = vm.createContext({ URL, location:{origin:'https://example.com'}, document:{
        addEventListener: (_, handler) => { click = handler; },
        head:{append: script => { apiScript = script; }},
        createElement: tag => tag === 'script' ? {} : (iframe = {style:{}, isConnected:false, focus() {}})
    }});
    vm.runInContext(source, context);
    assert.equal(apiScript, undefined);
    const button = {dataset:{foundryYoutubePlay:'https://www.youtube-nocookie.com/embed/M7lc1UVf-VE'}, replaceWith() {}};
    click({target:{closest:() => button}});
    assert.equal(apiScript.src, 'https://www.youtube.com/iframe_api');
    context.YT = {Player: class {constructor() { constructed++; }}};
    context.onYouTubeIframeAPIReady();
    await Promise.resolve();
    await Promise.resolve();
    assert.equal(constructed, 0);
});
