if (part) {
  const columns = part.querySelector(":scope > .foundry-masonry__columns");
  if (columns) {
    columns.__foundryMasonryCleanup?.();

    const items = Array.from(columns.children).filter((element) =>
      element.classList.contains("foundry-masonry__item")
    );
    let frame = 0;
    let disposed = false;
    let measuredWidth = -1;

    const layout = () => {
      frame = 0;
      if (disposed || !columns.isConnected) return;

      const style = getComputedStyle(columns);
      const requestedColumns = Number.parseInt(
        style.getPropertyValue("--foundry-masonry-column-count"),
        10
      );
      const columnCount = Math.max(1, Math.min(
        Number.isFinite(requestedColumns) ? requestedColumns : 1,
        Math.max(1, items.length)
      ));
      const parsedGap = Number.parseFloat(style.columnGap);
      const gap = Number.isFinite(parsedGap) ? parsedGap : 0;
      const width = columns.clientWidth;
      measuredWidth = width;
      if (width <= 0) return;

      const columnWidth = Math.max(0, (width - gap * (columnCount - 1)) / columnCount);
      columns.setAttribute("data-foundry-masonry-layout", "");
      items.forEach((item) => {
        item.style.width = `${columnWidth}px`;
      });

      const heights = Array(columnCount).fill(0);
      items.forEach((item) => {
        let column = 0;
        for (let index = 1; index < heights.length; index += 1) {
          if (heights[index] < heights[column]) column = index;
        }
        item.style.left = `${column * (columnWidth + gap)}px`;
        item.style.top = `${heights[column]}px`;
        heights[column] += item.offsetHeight + gap;
      });
      columns.style.height = `${Math.max(0, ...heights) - (items.length ? gap : 0)}px`;
    };

    const schedule = () => {
      if (disposed || frame) return;
      frame = requestAnimationFrame(layout);
    };
    const observer = new ResizeObserver((entries) => {
      if (entries.some((entry) => entry.target !== columns)) {
        schedule();
        return;
      }
      const width = entries[0]?.contentRect.width ?? columns.clientWidth;
      if (Math.abs(width - measuredWidth) > 0.25) schedule();
    });
    observer.observe(columns);
    items.forEach((item) => observer.observe(item));

    const images = items.flatMap((item) => Array.from(item.querySelectorAll("img")));
    images.forEach((image) => {
      image.addEventListener("load", schedule);
      image.addEventListener("error", schedule);
      image.decode?.().then(schedule, schedule);
    });
    document.fonts?.ready.then(schedule);

    const cleanup = () => {
      if (disposed) return;
      disposed = true;
      if (frame) cancelAnimationFrame(frame);
      observer.disconnect();
      images.forEach((image) => {
        image.removeEventListener("load", schedule);
        image.removeEventListener("error", schedule);
      });
      items.forEach((item) => {
        item.style.removeProperty("width");
        item.style.removeProperty("left");
        item.style.removeProperty("top");
      });
      columns.style.removeProperty("height");
      columns.removeAttribute("data-foundry-masonry-layout");
      if (columns.__foundryMasonryCleanup === cleanup) {
        delete columns.__foundryMasonryCleanup;
      }
    };
    columns.__foundryMasonryCleanup = cleanup;
    foundry.cleanup(cleanup);
    schedule();
  }
}
