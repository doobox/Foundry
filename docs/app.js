const base = document.body.dataset.base || "";

const favicon = document.createElement("link");
favicon.rel = "icon";
favicon.type = "image/png";
favicon.href = `${base}assets/foundry-icon.png`;
document.head.append(favicon);

const controlLinks = [
    ["Overview", "custom-controls.html"],
    ["Text", "text-control.html"],
    ["Text area", "text-area-control.html"],
    ["Link", "link-control.html"],
    ["Number", "number-control.html"],
    ["Slider", "slider-control.html"],
    ["Date", "date-control.html"],
    ["Colour", "colour.html"],
    ["Select", "select-control.html"],
    ["Toggle", "toggle-control.html"],
    ["Details", "details-control.html"],
    ["Button", "button-control.html"],
    ["Image", "image-control.html"],
    ["Image transform", "image-transform-control.html"],
    ["Math", "math-control.html"],
    ["Text alignment", "text-alignment.html"],
    ["Font family", "font-family.html"],
    ["Font size", "font-size.html"],
    ["Info", "info-control.html"],
    ["Divider", "divider-control.html"],
    ["Control arrays", "control-arrays.html"]
];

const sections = [
    { title: "Get started", links: [["Overview", "index.html"], ["Build a component", "quick-start.html"]] },
    { title: "Packages", links: [["Pack structure", "bundle-structure.html"], ["Nested packs", "nested-packs.html"]] },
    { title: "Build components", links: [["Templates", "template-values.html"], ["Custom controls", "custom-controls.html", controlLinks], ["Editable text", "editable-text.html"], ["Child components", "slots.html"]] },
    { title: "Themes", links: [["Theme values", "theme-controls.html"]] },
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
            links: section.links.filter(([label, , children]) => !normalized || `${section.title} ${label} ${(children || []).map(([child]) => child).join(" ")}`.toLowerCase().includes(normalized))
        })).filter(section => section.links.length);
        container.innerHTML = visible.length ? visible.map(section => `
            <section class="nav-section">
                <h2 class="nav-heading">${section.title}</h2>
                <ul>${section.links.map(([label, href, children]) => {
                    const branchActive = href === current || (children || []).some(([, childHref]) => childHref === current);
                    return `<li class="${children ? "nav-branch" : ""}"><a ${href === current ? 'aria-current="page"' : ""} href="${base}${href}">${label}</a>${children && (branchActive || normalized) ? `<ul class="nav-children">${children.filter(([child]) => !normalized || child.toLowerCase().includes(normalized)).map(([child, childHref]) => `<li><a ${childHref === current ? 'aria-current="page"' : ""} href="${base}${childHref}">${child}</a></li>`).join("")}</ul>` : ""}</li>`;
                }).join("")}</ul>
            </section>`).join("") : '<p class="nav-empty">No matching topics.</p>';
    };
    render();
    nav.querySelector(".search").addEventListener("input", event => render(event.target.value));
}

if (controlLinks.some(([, href]) => href === (window.location.pathname.split("/").pop() || "index.html"))) {
    const breadcrumbs = document.querySelector(".breadcrumbs");
    if (breadcrumbs && !breadcrumbs.querySelector('a[href="custom-controls.html"]')) {
        breadcrumbs.innerHTML = `<a href="${base}index.html">Foundry Developer</a><span>›</span><a href="${base}custom-controls.html">Custom controls</a>`;
    }
}

const referenceTypeByPage = {
    "colour.html": "color",
    "link-control.html": "link",
    "text-alignment.html": "textAlignment",
    "font-family.html": "fontFamily",
    "font-size.html": "fontSize"
};
const referenceType = referenceTypeByPage[window.location.pathname.split("/").pop()];
if (referenceType) {
    document.body.dataset.control = referenceType;
    const referenceScript = document.createElement("script");
    referenceScript.src = `${base}control-reference.js`;
    document.head.append(referenceScript);
}
