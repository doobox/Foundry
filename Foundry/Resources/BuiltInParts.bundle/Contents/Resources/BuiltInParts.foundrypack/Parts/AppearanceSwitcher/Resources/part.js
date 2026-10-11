if (part) {
  const trigger = part.querySelector('[data-bs-toggle="menu"]');
  const icon = part.querySelector('[data-current-icon]');
  const options = part.querySelectorAll('[data-mode]');
  const appearance = window.foundryAppearance;
  const modes = {
    light: { icon: 'sun-fill', label: 'Light' },
    dark: { icon: 'moon-stars-fill', label: 'Dark' },
    system: { icon: 'circle-half', label: 'Auto' }
  };
  if (appearance) {
    const update = () => {
      const mode = appearance.get();
      icon.className = `bi bi-${modes[mode].icon}`;
      trigger.setAttribute('aria-label', `Colour mode: ${modes[mode].label}`);
      options.forEach(option => {
        const active = option.dataset.mode === mode;
        option.classList.toggle('active', active);
        option.setAttribute('aria-pressed', String(active));
        option.querySelector('[data-check]').hidden = !active;
      });
    };
    options.forEach(option => option.addEventListener('click', () => appearance.set(option.dataset.mode)));
    window.addEventListener('foundry:appearance-change', update);
    update();
  } else {
    trigger.disabled = true;
    trigger.title = 'Enable Allow dark mode in Site Settings to use this switcher.';
  }
}
