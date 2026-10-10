import Foundation

nonisolated enum FoundryLightbox {
    static let javaScript = #"""
    (() => {
      if (globalThis.foundryLightbox) return;
      let dialog, body, closeButton, active, overflow, closing = false;
      const interactive = 'a,button,input,select,textarea,summary,[contenteditable="true"],[tabindex]';
      const ensureDialog = () => {
        if (dialog) return;
        const style = document.createElement('style');
        style.textContent = `
          dialog.fd-lightbox{box-sizing:border-box;border:0;padding:0;width:min(1100px,calc(100vw - 48px));max-width:calc(100vw - 48px);max-height:calc(100dvh - 112px);background:transparent;color:inherit;overflow:visible}
          dialog.fd-lightbox::backdrop{background:var(--fd-lightbox-backdrop,rgb(0 0 0 / .5));backdrop-filter:blur(var(--fd-lightbox-blur,0px));-webkit-backdrop-filter:blur(var(--fd-lightbox-blur,0px))}
          dialog.fd-lightbox[open],dialog.fd-lightbox[open]::backdrop{animation:fd-lightbox-fade-in 220ms ease-out both}
          dialog.fd-lightbox[open] .fd-lightbox-body{animation:fd-lightbox-scale-in 220ms cubic-bezier(.2,.8,.2,1) both}
          dialog.fd-lightbox.fd-lightbox-closing,dialog.fd-lightbox.fd-lightbox-closing::backdrop{animation:fd-lightbox-fade-out 160ms ease-in both}
          dialog.fd-lightbox.fd-lightbox-closing .fd-lightbox-body{animation:fd-lightbox-scale-out 160ms ease-in both}
          @keyframes fd-lightbox-fade-in{from{opacity:0}to{opacity:1}}
          @keyframes fd-lightbox-fade-out{from{opacity:1}to{opacity:0}}
          @keyframes fd-lightbox-scale-in{from{transform:translateY(8px) scale(.97)}to{transform:none}}
          @keyframes fd-lightbox-scale-out{from{transform:none}to{transform:translateY(4px) scale(.98)}}
          @media(prefers-reduced-motion:reduce){dialog.fd-lightbox[open],dialog.fd-lightbox[open]::backdrop,dialog.fd-lightbox[open] .fd-lightbox-body{animation:none}}
          .fd-lightbox-body{max-height:calc(100dvh - 112px);overflow:auto;overscroll-behavior:contain}
          .fd-lightbox-close{position:fixed;right:16px;top:16px;display:grid;place-items:center;width:40px;height:40px;padding:0;border:1px solid rgb(255 255 255 / .25);border-radius:50%;font:28px system-ui;cursor:pointer;background:rgb(20 20 20 / .7);color:white;box-shadow:0 2px 12px rgb(0 0 0 / .2)}
          .fd-lightbox-close:focus-visible{outline:2px solid currentColor;outline-offset:2px}
          .fd-lightbox-body[data-media] > img,.fd-lightbox-body[data-media] > video,.fd-lightbox-body[data-media] > svg{display:block;width:100%;height:auto;max-height:calc(100dvh - 112px);object-fit:contain;margin:auto}
          .fd-lightbox-body[data-media] > iframe{display:block;width:100%;aspect-ratio:16/9;border:0;min-height:200px}
          .fd-lightbox-trigger{position:relative;display:block;width:100%;aspect-ratio:16/9;padding:0;border:0;background:#161616;cursor:pointer;overflow:hidden}
          .fd-lightbox-trigger img{display:block;width:100%;height:100%;object-fit:cover}
          .fd-lightbox-trigger span{position:absolute;inset:0;display:grid;place-items:center;color:white;font:48px system-ui;text-shadow:0 2px 8px black}
        `;
        document.head.append(style);
        dialog = document.createElement('dialog');
        dialog.className = 'fd-lightbox';
        closeButton = document.createElement('button');
        closeButton.type = 'button';
        closeButton.className = 'fd-lightbox-close';
        closeButton.setAttribute('aria-label', 'Close lightbox');
        closeButton.textContent = '×';
        body = document.createElement('div');
        body.className = 'fd-lightbox-body';
        dialog.append(closeButton, body);
        document.body.append(dialog);
        closeButton.addEventListener('click', dismiss);
        dialog.addEventListener('cancel', event => { event.preventDefault(); dismiss(); });
        dialog.addEventListener('click', event => {
          if (event.target !== dialog || !active) return;
          const rect = dialog.getBoundingClientRect();
          if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dismiss();
        });
        dialog.addEventListener('close', () => { if (!dialog.open) cleanup(); });
      };
      const dismiss = async () => {
        if (!dialog?.open || closing) return;
        closing = true;
        const current = active;
        body.querySelectorAll('video,audio').forEach(media => media.pause());
        dialog.classList.add('fd-lightbox-closing');
        await Promise.all(dialog.getAnimations({subtree:true})
          .filter(animation => animation.animationName?.startsWith('fd-lightbox-'))
          .map(animation => animation.finished.catch(() => {})));
        if (active === current && closing) dialog.close();
      };
      const cleanup = () => {
        if (!active) return;
        body.querySelectorAll('video,audio').forEach(media => media.pause());
        body.querySelectorAll('iframe').forEach(frame => {
          frame.dataset.foundryLightboxSource = frame.src;
          frame.src = 'about:blank';
        });
        active.restore?.();
        body.replaceChildren();
        document.documentElement.style.overflow = overflow;
        const trigger = active.trigger;
        active = null;
        closing = false;
        dialog.classList.remove('fd-lightbox-closing');
        if (trigger?.isConnected) trigger.focus();
      };
      const own = (root, config, selector) => Array.from(root.querySelectorAll(selector)).find(node =>
        !config.contains(node) && node.closest('[data-foundry-id]') === root);
      const iframeFor = address => {
        const url = new URL(address, location.href);
        if (!['https://www.youtube.com','https://www.youtube-nocookie.com'].includes(url.origin)
            || !/^\/embed\/[A-Za-z0-9_-]{11}$/.test(url.pathname)) return null;
        url.searchParams.set('autoplay', '1');
        url.searchParams.set('enablejsapi', '1');
        url.searchParams.set('origin', location.origin);
        const frame = document.createElement('iframe');
        frame.src = url.href;
        frame.title = 'YouTube video';
        frame.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
        frame.allowFullscreen = true;
        frame.referrerPolicy = 'strict-origin-when-cross-origin';
        return frame;
      };
      const open = (root, config, trigger, mediaSource) => {
        ensureDialog();
        if (dialog.open) { dialog.close(); cleanup(); }
        let content, restore;
        const holder = own(root, config, '[data-foundry-lightbox-content]');
        const source = holder || mediaSource;
        if (!source) return;
        const play = source.matches?.('[data-foundry-youtube-play]') ? source : source.querySelector?.('[data-foundry-youtube-play]');
        const native = source.matches?.('video') ? source : source.querySelector?.('video');
        if (holder) {
          content = holder;
          const marker = document.createComment('Foundry lightbox content');
          holder.before(marker);
          restore = () => marker.replaceWith(holder);
          holder.querySelectorAll('iframe[data-foundry-lightbox-source]').forEach(frame => { frame.src = frame.dataset.foundryLightboxSource; });
        } else if (play) content = iframeFor(play.dataset.foundryYoutubePlay);
        else if (source.matches?.('iframe')) content = iframeFor(source.src);
        else if (source.querySelector?.('iframe')) content = iframeFor(source.querySelector('iframe').src);
        else if (native) {
          content = native.cloneNode(true);
          content.removeAttribute('id');
          content.controls = true;
          content.autoplay = true;
        } else {
          const image = source.matches?.('img,svg') ? source : source.querySelector?.('img,svg');
          if (image?.matches('svg')) {
            content = image;
            // Keep paints resolved from the part's ancestor-scoped CSS while
            // moving the original SVG (cloning would duplicate its IDs).
            const paints = ['color','fill','fill-opacity','fill-rule','stroke','stroke-opacity','stroke-width','stroke-linecap','stroke-linejoin','stroke-dasharray','stroke-dashoffset','opacity','vector-effect'];
            const styles = [image, ...image.querySelectorAll('*')].map(node => {
              const computed = getComputedStyle(node);
              return {node, original:node.getAttribute('style'), values:paints.map(key => [key,computed.getPropertyValue(key)])};
            });
            styles.forEach(({node,values}) => values.forEach(([key,value]) => node.style.setProperty(key,value,'important')));
            const marker = document.createComment('Foundry lightbox SVG');
            image.before(marker);
            restore = () => {
              marker.replaceWith(image);
              styles.forEach(({node,original}) => original === null ? node.removeAttribute('style') : node.setAttribute('style',original));
            };
          } else if (image) {
            content = image.cloneNode(true); content.removeAttribute('id');
            content.removeAttribute('srcset'); content.removeAttribute('sizes');
            content.loading = 'eager';
          }
        }
        if (!content) return;
        active = {trigger, restore};
        overflow = document.documentElement.style.overflow;
        document.documentElement.style.overflow = 'hidden';
        const backdrop = config.style.color ? getComputedStyle(config).color : config.dataset.backdropColor;
        dialog.style.setProperty('--fd-lightbox-backdrop', backdrop || 'rgb(0 0 0 / .5)');
        dialog.style.setProperty('--fd-lightbox-blur', Math.min(40, Math.max(0, Number(config.dataset.backdropBlur) || 0)) + 'px');
        dialog.setAttribute('aria-label', holder?.getAttribute('aria-label') || mediaSource?.getAttribute('alt') || 'Lightbox');
        body.toggleAttribute('data-media', !holder);
        body.append(content);
        dialog.showModal();
        closeButton.focus();
        if (content.matches('iframe')) globalThis.foundryStartYouTube?.(content);
        if (content.matches('video')) content.play().catch(() => {});
      };
      globalThis.foundryLightbox = {connect(root, config) {
        if (config.dataset.connected) return;
        ensureDialog();
        config.dataset.connected = 'true';
        let trigger;
        const media = Array.from(root.querySelectorAll('[data-foundry-youtube-play],video,iframe,img,svg')).find(node =>
          !config.contains(node) && !node.closest('.background-layer') && node.closest('[data-foundry-id]') === root);
        const customTrigger = own(root, config, '[data-foundry-lightbox-trigger]');
        if (customTrigger) {
          const actions = Array.from(customTrigger.querySelectorAll(interactive));
          // One action only: never swallow forms or a card's competing links.
          if (actions.length > 1 || actions.some(node => !node.matches('button,a'))) return;
          trigger = actions[0] || customTrigger;
        } else if (media?.matches('[data-foundry-youtube-play]')) trigger = media;
        else if (media?.matches('video,iframe')) {
          trigger = document.createElement('button');
          trigger.type = 'button';
          trigger.className = media.className + ' fd-lightbox-trigger';
          trigger.setAttribute('aria-label','Play video in lightbox');
          const poster = media.poster;
          const youtubeID = media.matches('iframe') && /\/embed\/([A-Za-z0-9_-]{11})(?:[?]|$)/.exec(media.src)?.[1];
          if (poster || youtubeID) {
            const image = document.createElement('img');
            image.src = poster || 'https://i.ytimg.com/vi/' + youtubeID + '/maxresdefault.jpg';
            if (youtubeID) image.dataset.foundryYoutubeThumbnail = youtubeID;
            image.alt = ''; trigger.append(image);
          }
          const icon = document.createElement('span'); icon.textContent = '▶'; icon.setAttribute('aria-hidden','true'); trigger.append(icon);
          if (media.matches('video')) media.pause();
          media.replaceWith(trigger);
        } else {
          if (!media || Array.from(root.querySelectorAll(interactive)).some(node => !config.contains(node))) return;
          trigger = root;
        }
        if (trigger.matches('a')) { trigger.removeAttribute('href'); trigger.removeAttribute('target'); }
        if (!trigger.matches('button,a[href]')) { trigger.tabIndex = 0; trigger.setAttribute('role','button'); }
        trigger.setAttribute('aria-haspopup','dialog');
        if (!trigger.hasAttribute('aria-label') && !trigger.textContent.trim()) trigger.setAttribute('aria-label', media?.getAttribute('alt') || 'Open lightbox');
        const activate = event => {
          if (event.target.closest('[data-foundry-lightbox-config]')) return;
          if (trigger === root && event.target.closest(interactive) !== root && event.target.closest(interactive)) return;
          event.preventDefault(); event.stopImmediatePropagation();
          open(root,config,trigger,media);
        };
        trigger.addEventListener('click',activate,true);
        trigger.addEventListener('keydown',event => {
          if (event.target === trigger && !trigger.matches('button,a[href]') && ['Enter',' '].includes(event.key)) activate(event);
        });
      }};
    })();
    """#
}
