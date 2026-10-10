import Foundation

nonisolated enum YouTubePosterPlayback {
    static let javaScript = #"""
    (() => {
      if (globalThis.foundryYouTubePosterPlayback) return;
      globalThis.foundryYouTubePosterPlayback = true;
      let apiReady;
      const loadAPI = () => {
        if (globalThis.YT?.Player) return Promise.resolve(globalThis.YT);
        if (apiReady) return apiReady;
        apiReady = new Promise((resolve, reject) => {
          const previous = globalThis.onYouTubeIframeAPIReady;
          globalThis.onYouTubeIframeAPIReady = () => {
            try { previous?.(); } finally { resolve(globalThis.YT); }
          };
          const script = document.createElement('script');
          script.src = 'https://www.youtube.com/iframe_api';
          script.onerror = reject;
          document.head.append(script);
        });
        return apiReady;
      };
      globalThis.foundryStartYouTube = player => {
        loadAPI().then(YT => {
          if (!player.isConnected) return;
          new YT.Player(player, {
            events: {
              onReady: event => {
                if (player.isConnected) event.target.playVideo();
              },
              onAutoplayBlocked: () => {
                // Leave the real player's controls available; do not cover it
                // or repeatedly retry against the browser's playback policy.
                player.dataset.foundryPlaybackBlocked = 'true';
              }
            }
          });
        }).catch(() => {
          // The iframe still works manually if the API script is unavailable.
        });
      };
      document.addEventListener('click', event => {
        const button = event.target.closest?.('button[data-foundry-youtube-play]');
        if (!button) return;
        const source = new URL(button.dataset.foundryYoutubePlay);
        if (source.origin !== 'https://www.youtube-nocookie.com' || !/^\/embed\/[A-Za-z0-9_-]{11}$/.test(source.pathname)) return;
        source.searchParams.set('autoplay', '1');
        source.searchParams.set('enablejsapi', '1');
        source.searchParams.set('origin', location.origin);
        const player = document.createElement('iframe');
        player.title = 'YouTube video';
        player.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
        player.allowFullscreen = true;
        player.referrerPolicy = 'strict-origin-when-cross-origin';
        player.style.cssText = 'display:block;width:100%;height:100%;border:0;min-height:200px;position:absolute;inset:0';
        player.src = source.href;
        button.replaceWith(player);
        player.focus();
        globalThis.foundryStartYouTube(player);
      });
    })();
    """#
}
