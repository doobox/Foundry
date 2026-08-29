const base = document.body.dataset.base || "";

const sections = [
    {
        title: "Start here",
        links: [
            ["Overview", "index.html"],
            ["Component quick start", "quick-start.html"]
        ]
    },
    {
        title: "Component bundles",
        links: [
            ["Bundle structure", "bundle-structure.html"],
            ["Info.plist", "info-plist.html"]
        ]
    },
    {
        title: "Templates",
        links: [
            ["Editable text", "editable-text.html"]
        ]
    },
    {
        title: "Theme controls",
        links: [
            ["Overview", "theme-controls.html"],
            ["Font family", "font-family.html"],
            ["Font size", "font-size.html"]
        ]
    },
    {
        title: "Reference",
        links: [
            ["Component API index", "components.html"]
        ]
    }
];

const nav = document.querySelector("[data-doc-nav]");
if (nav) {
    const current = window.location.pathname.split("/").pop() || "index.html";
    nav.innerHTML = `
        <a class="brand" href="${base}index.html">Foundry API</a>
        <input class="search" type="search" placeholder="Filter documentation" aria-label="Filter documentation">
        <div data-nav-sections></div>
    `;
    const container = nav.querySelector("[data-nav-sections]");
    const render = (query = "") => {
        const normalized = query.trim().toLowerCase();
        const visibleSections = sections.map(section => ({
            ...section,
            links: section.links.filter(([label]) => !normalized || `${section.title} ${label}`.toLowerCase().includes(normalized))
        })).filter(section => section.links.length);
        container.innerHTML = visibleSections.length ? visibleSections.map(section => `
            <section class="nav-section">
                <h2 class="nav-heading">${section.title}</h2>
                <ul>${section.links.map(([label, href]) => `
                    <li><a ${href === current ? 'aria-current="page"' : ""} href="${base}${href}">${label}</a></li>
                `).join("")}</ul>
            </section>
        `).join("") : '<p class="nav-empty">No matching documentation.</p>';
    };
    render();
    nav.querySelector(".search").addEventListener("input", event => render(event.target.value));
}
