{{ if !canvas }}
const toggle = part.querySelector('[data-navigation-toggle]');
const menu = part.querySelector('[data-navigation-menu]');

if (toggle && menu) {
    const menuID = `fd-navigation-menu-${Math.random().toString(36).slice(2)}`;
    menu.id = menuID;
    toggle.setAttribute('aria-controls', menuID);
}

const setToggleState = open => {
    if (!toggle) { return; }
    toggle.classList.toggle('is-open', open);
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
};

const setDropdownState = (item, open) => {
    item.classList.toggle('is-open', open);
    const disclosure = item.querySelector('[data-navigation-disclosure]');
    if (disclosure) { disclosure.setAttribute('aria-expanded', String(open)); }

    const dropdown = item.querySelector('[data-navigation-dropdown]');
    if (dropdown) {
        dropdown.classList.remove('align-end');
        if (open && dropdown.getBoundingClientRect().right > document.documentElement.clientWidth) {
            dropdown.classList.add('align-end');
        }
    }
};

const closeDropdowns = exception => {
    part.querySelectorAll('.fd-navigation__item.is-open').forEach(item => {
        if (item === exception) { return; }
        setDropdownState(item, false);
    });
};

const closeMenu = () => {
    closeDropdowns();
    if (menu && menu.classList.contains('is-open')) {
        menu.classList.remove('is-open');
        setToggleState(false);
    }
};

if (toggle && menu) {
    toggle.addEventListener('click', () => {
        const open = menu.classList.toggle('is-open');
        setToggleState(open);
        if (!open) { closeDropdowns(); }
    });
}

part.querySelectorAll('[data-navigation-disclosure]').forEach(disclosure => {
    disclosure.addEventListener('click', event => {
        event.preventDefault();
        const item = disclosure.closest('.fd-navigation__item');
        if (!item) { return; }
        const open = !item.classList.contains('is-open');
        setDropdownState(item, open);
        if (open) { closeDropdowns(item); }
    });
});

document.addEventListener('click', event => {
    if (!part.contains(event.target)) { closeMenu(); }
});

part.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
        const openDisclosure = part.querySelector('.fd-navigation__item.is-open [data-navigation-disclosure]');
        const menuWasOpen = Boolean(menu && menu.classList.contains('is-open'));
        closeMenu();
        if (openDisclosure) {
            openDisclosure.focus();
        } else if (menuWasOpen && toggle) {
            toggle.focus();
        }
    }
});
{{ endif }}
