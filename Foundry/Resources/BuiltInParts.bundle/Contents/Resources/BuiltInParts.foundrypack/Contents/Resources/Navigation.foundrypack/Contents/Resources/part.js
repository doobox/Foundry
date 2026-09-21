{{ if !canvas }}
const toggle = part.querySelector('[data-navigation-toggle]');
const menu = part.querySelector('[data-navigation-menu]');

const closeDropdowns = exception => {
    part.querySelectorAll('.fd-navigation__item.is-open').forEach(item => {
        if (item === exception) { return; }
        item.classList.remove('is-open');
        const disclosure = item.querySelector('[data-navigation-disclosure]');
        if (disclosure) { disclosure.setAttribute('aria-expanded', 'false'); }
    });
};

const closeMenu = () => {
    closeDropdowns();
    if (menu && menu.classList.contains('is-open')) {
        menu.classList.remove('is-open');
        if (toggle) {
            toggle.classList.remove('is-open');
            toggle.setAttribute('aria-expanded', 'false');
        }
    }
};

if (toggle && menu) {
    toggle.addEventListener('click', () => {
        const open = menu.classList.toggle('is-open');
        toggle.classList.toggle('is-open', open);
        toggle.setAttribute('aria-expanded', String(open));
        if (!open) { closeDropdowns(); }
    });
}

part.querySelectorAll('[data-navigation-disclosure]').forEach(disclosure => {
    disclosure.addEventListener('click', event => {
        event.preventDefault();
        const item = disclosure.closest('.fd-navigation__item');
        if (!item) { return; }
        const open = item.classList.toggle('is-open');
        disclosure.setAttribute('aria-expanded', String(open));
        if (open) { closeDropdowns(item); }
    });
});

document.addEventListener('click', event => {
    if (!part.contains(event.target)) { closeMenu(); }
});

part.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
        closeMenu();
        if (toggle) { toggle.focus(); }
    }
});
{{ endif }}
