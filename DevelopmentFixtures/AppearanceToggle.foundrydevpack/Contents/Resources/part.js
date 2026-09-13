const appearanceButtons = part.querySelectorAll('[data-appearance-choice]');
if (typeof window.foundryAppearance?.set === 'function') {
    appearanceButtons.forEach(button => {
        button.addEventListener('click', () => {
            window.foundryAppearance.set(button.dataset.appearanceChoice);
        });
    });
} else {
    appearanceButtons.forEach(button => { button.disabled = true; });
    const hint = part.querySelector('[data-appearance-hint]');
    if (hint) hint.textContent = 'Use browser Preview with Light and Dark enabled in Site Settings.';
}
