const base = document.body.dataset.base || "";

const favicon = document.createElement("link");
favicon.rel = "icon";
favicon.type = "image/png";
favicon.href = `${base}assets/foundry-icon.png`;
document.head.append(favicon);

const sections = [
    { title: "Get started", links: [["Overview", "index.html"], ["Build a component", "quick-start.html"]] },
    { title: "Packages", links: [["Pack structure", "bundle-structure.html"], ["Nested packs", "nested-packs.html"]] },
    { title: "Build components", links: [["Templates", "template-values.html"], ["Custom controls", "custom-controls.html"], ["Colour", "colour.html"], ["Editable text", "editable-text.html"], ["Child components", "slots.html"]] },
    { title: "Smart controls", links: [["Overview", "theme-controls.html"], ["Text alignment", "text-alignment.html"], ["Font family", "font-family.html"], ["Font size", "font-size.html"]] },
    { title: "Reference", links: [["Info.plist", "info-plist.html"], ["API index", "components.html"]] }
];

const nav = document.querySelector("[data-doc-nav]");
if (nav) {
    const current = window.location.pathname.split("/").pop() || "index.html";
    nav.innerHTML = `
        <a class="brand" href="${base}index.html"><img class="brand-mark" src="${base}assets/foundry-icon.png" alt=""><span>Foundry Developer</span></a>
        <input class="search" type="search" placeholder="Search topics" aria-label="Filter documentation">
        <div data-nav-sections></div>
        <a class="nav-todo" ${current === "todo.html" ? 'aria-current="page"' : ""} href="${base}todo.html">TODO</a>`;
    const container = nav.querySelector("[data-nav-sections]");
    const render = (query = "") => {
        const normalized = query.trim().toLowerCase();
        const visible = sections.map(section => ({
            ...section,
            links: section.links.filter(([label]) => !normalized || `${section.title} ${label}`.toLowerCase().includes(normalized))
        })).filter(section => section.links.length);
        container.innerHTML = visible.length ? visible.map(section => `
            <section class="nav-section">
                <h2 class="nav-heading">${section.title}</h2>
                <ul>${section.links.map(([label, href]) => `<li><a ${href === current ? 'aria-current="page"' : ""} href="${base}${href}">${label}</a></li>`).join("")}</ul>
            </section>`).join("") : '<p class="nav-empty">No matching topics.</p>';
    };
    render();
    nav.querySelector(".search").addEventListener("input", event => render(event.target.value));
}
