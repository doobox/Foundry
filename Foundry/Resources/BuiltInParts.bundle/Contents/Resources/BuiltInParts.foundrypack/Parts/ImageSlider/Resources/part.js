{{ if !canvas }}
const slides = Array.from(part.querySelectorAll('[data-slide-index]'));
const dots = Array.from(part.querySelectorAll('[data-slider-dot]'));
const previousButton = part.querySelector('[data-slider-previous]');
const nextButton = part.querySelector('[data-slider-next]');
const loops = part.dataset.loop === 'true';
const autoplays = part.dataset.autoplay === 'true';
const pausesOnHover = part.dataset.pauseOnHover === 'true';
const interval = Math.max(2, Number(part.dataset.interval) || 5) * 1000;
const reducesMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
let currentIndex = 0;
let timer = null;

const showSlide = requestedIndex => {
    if (slides.length === 0) return;
    if (loops) {
        currentIndex = (requestedIndex + slides.length) % slides.length;
    } else {
        currentIndex = Math.max(0, Math.min(requestedIndex, slides.length - 1));
    }

    slides.forEach((slide, index) => {
        const active = index === currentIndex;
        slide.classList.toggle('is-active', active);
        slide.hidden = !active;
        slide.setAttribute('aria-hidden', String(!active));
    });
    dots.forEach((dot, index) => {
        const active = index === currentIndex;
        dot.classList.toggle('is-active', active);
        if (active) dot.setAttribute('aria-current', 'true');
        else dot.removeAttribute('aria-current');
    });
    if (previousButton) previousButton.disabled = !loops && currentIndex === 0;
    if (nextButton) nextButton.disabled = !loops && currentIndex === slides.length - 1;
};

const stopAutoplay = () => {
    if (timer !== null) window.clearInterval(timer);
    timer = null;
};

const startAutoplay = () => {
    stopAutoplay();
    if (autoplays && !reducesMotion && slides.length > 1) {
        timer = window.setInterval(() => showSlide(currentIndex + 1), interval);
    }
};

previousButton?.addEventListener('click', () => {
    showSlide(currentIndex - 1);
    startAutoplay();
});
nextButton?.addEventListener('click', () => {
    showSlide(currentIndex + 1);
    startAutoplay();
});
dots.forEach((dot, index) => dot.addEventListener('click', () => {
    showSlide(index);
    startAutoplay();
}));

part.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft') {
        event.preventDefault();
        showSlide(currentIndex - 1);
        startAutoplay();
    } else if (event.key === 'ArrowRight') {
        event.preventDefault();
        showSlide(currentIndex + 1);
        startAutoplay();
    }
});

if (pausesOnHover) {
    part.addEventListener('mouseenter', stopAutoplay);
    part.addEventListener('mouseleave', startAutoplay);
}
part.addEventListener('focusin', stopAutoplay);
part.addEventListener('focusout', startAutoplay);
document.addEventListener('visibilitychange', () => {
    if (document.hidden) stopAutoplay();
    else startAutoplay();
});

showSlide(0);
startAutoplay();
{{ endif }}
