import Foundation

/// Runs in the editor's isolated world; page scripts remain disabled.
nonisolated enum CanvasYouTubeThumbnails {
    static let javaScript = #"""
    (() => {
      if (globalThis.foundryYouTubeThumbnails) return;
      globalThis.foundryYouTubeThumbnails = true;
      const selector = 'img[data-foundry-youtube-thumbnail]';
      const prepare = image => {
        if (image.dataset.foundryThumbnailReady) return;
        image.dataset.foundryThumbnailReady = 'true';
        const id = image.dataset.foundryYoutubeThumbnail;
        if (!/^[A-Za-z0-9_-]{11}$/.test(id)) return;
        const sizes = ['maxresdefault', 'sddefault', 'hqdefault', 'mqdefault'];
        let index = 0;
        const next = () => {
          if (++index < sizes.length) {
            image.src = 'https://i.ytimg.com/vi/' + id + '/' + sizes[index] + '.jpg';
          } else {
            image.style.visibility = 'hidden';
            const label = document.createElement('span');
            label.textContent = 'YouTube thumbnail unavailable';
            label.style.cssText = 'position:absolute;inset:0;display:grid;place-items:center;color:white;font:14px system-ui';
            image.parentElement.append(label);
          }
        };
        image.addEventListener('error', next);
        image.addEventListener('load', () => { if (image.naturalWidth <= 120) next(); });
        if (image.complete && image.naturalWidth <= 120) next();
      };
      const scan = () => document.querySelectorAll(selector).forEach(prepare);
      scan();
      new MutationObserver(scan).observe(document.documentElement, {childList:true, subtree:true});
    })();
    """#
}
