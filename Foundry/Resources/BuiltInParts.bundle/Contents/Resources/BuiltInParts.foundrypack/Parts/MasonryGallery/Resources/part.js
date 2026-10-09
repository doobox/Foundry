const masonryGallery = document.querySelector('[data-foundry-id="{{ instance.id }}"]');

if (masonryGallery) {
  masonryGallery.querySelectorAll(".foundry-masonry__media").forEach((media) => {
    const image = media.querySelector(".foundry-masonry__image");
    if (!image) return;

    const enableGeometryZoom = () => {
      if (media.classList.contains("foundry-masonry__media--natural")) {
        if (!image.naturalWidth || !image.naturalHeight) return;
        media.style.aspectRatio = `${image.naturalWidth} / ${image.naturalHeight}`;
      }
      media.classList.add("foundry-masonry__media--zoomable");
    };

    if (image.complete) enableGeometryZoom();
    else image.addEventListener("load", enableGeometryZoom, { once: true });
  });

  if (
    typeof GLightbox === "function" &&
    masonryGallery.querySelector("[data-foundry-masonry-lightbox]")
  ) {
    GLightbox({
      selector: '[data-foundry-masonry-lightbox="{{ instance.id }}"]',
      touchNavigation: true,
      loop: true
    });
  }
}
