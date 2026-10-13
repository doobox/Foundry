(() => {
  'use strict';

  if (!document.querySelector('.fd-markdown-code')) return;

  document.addEventListener('click', async (event) => {
    const button = event.target.closest('.fd-markdown-code-copy');
    if (!button) return;
    const code = button.closest('.fd-markdown-code')?.querySelector('pre code');
    if (!code) return;

    const source = code.textContent;
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(source);
      } else {
        const field = document.createElement('textarea');
        field.value = source;
        field.style.position = 'fixed';
        field.style.opacity = '0';
        document.body.append(field);
        field.select();
        const copied = document.execCommand('copy');
        field.remove();
        if (!copied) throw new Error('Copy command failed');
      }
      button.textContent = 'Copied';
      button.setAttribute('aria-label', 'Code copied');
    } catch {
      button.textContent = 'Copy failed';
      button.setAttribute('aria-label', 'Could not copy code');
    }
    clearTimeout(button._foundryResetTimer);
    button._foundryResetTimer = setTimeout(() => {
      button.textContent = 'Copy';
      button.setAttribute('aria-label', 'Copy code');
    }, 2000);
  });
})();
