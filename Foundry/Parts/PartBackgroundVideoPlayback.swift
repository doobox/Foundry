import Foundation

/// Shared across instances; observing the media accounts for clipping by ancestors.
nonisolated enum PartBackgroundVideoPlayback {
    static let javaScript = #"""
    (() => {
      if (!("IntersectionObserver" in window)) return;
      const root = document.querySelector('[data-foundry-id="{{ instance.id }}"]');
      if (!root) return;
      if (!window.foundryBackgroundPlayback) {
        const videos = new Map();
        const shouldPlay = (video) => videos.get(video) === true && !document.hidden && video.isConnected;
        const update = (video) => {
          if (!video.isConnected) {
            video.pause();
            observer.unobserve(video);
            videos.delete(video);
            return;
          }
          if (!shouldPlay(video)) { video.pause(); return; }
          if (video.ended && !video.loop) return;
          const pending = video.play();
          if (pending) pending.then(() => {
            if (!shouldPlay(video)) video.pause();
          }).catch(() => {});
        };
        const observer = new IntersectionObserver((entries) => {
          for (const entry of entries) {
            if (!videos.has(entry.target)) continue;
            videos.set(entry.target, entry.isIntersecting && entry.intersectionRatio > 0);
            update(entry.target);
          }
        });
        document.addEventListener("visibilitychange", () => videos.forEach((_, video) => update(video)));
        window.foundryBackgroundPlayback = {
          observe(video) {
            if (videos.has(video)) return;
            videos.set(video, false);
            video.pause();
            observer.observe(video);
          },
          unobserve(video) {
            if (!videos.has(video)) return;
            video.pause();
            observer.unobserve(video);
            videos.delete(video);
          }
        };
      }
      const ownedVideos = Array.from(root.querySelectorAll("video.foundry-background-video")).filter(
        (video) => video.closest("[data-foundry-id]") === root
      );
      ownedVideos.forEach((video) => window.foundryBackgroundPlayback.observe(video));
      globalThis.foundryRegisterCanvasScriptCleanup?.("{{ instance.id }}", () => {
        ownedVideos.forEach((video) => window.foundryBackgroundPlayback?.unobserve(video));
      });
    })();
    """#
}
