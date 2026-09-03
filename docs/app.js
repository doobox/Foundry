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
    ["Padding", "padding-control.html"],
    ["Margin", "margin-control.html"],
    ["Slider", "slider-control.html"],
    ["Date", "date-control.html"],
    ["Colour", "colour.html"],
    ["Icon", "icon-control.html"],
    ["Select", "select-control.html"],
    ["Toggle", "toggle-control.html"],
    ["Details", "details-control.html"],
    ["Button", "button-control.html"],
    ["Math", "math-control.html"],
    ["Text alignment", "text-alignment.html"],
    ["Font family", "font-family.html"],
    ["Font size", "font-size.html"],
    ["Line height", "line-height.html"],
    ["Info", "info-control.html"],
    ["Divider", "divider-control.html"],
    ["Control arrays", "control-arrays.html"],
    ["Conditional visibility", "enable-control.html"]
];

const templateLinks = [
    ["Primary HTML", "templates.html#primary-html"],
    ["CSS", "templates.html#css"],
    ["JavaScript", "templates.html#javascript"],
    ["PHP", "templates.html#php"],
    ["Additional HTML", "templates.html#additional-html"],
    ["Editor CSS", "templates.html#editor-css"]
];

const sections = [
    { title: "Start here", links: [["Overview", "index.html"], ["Build your first component", "quick-start.html"]] },
    { title: "Package", links: [["Bundle structure", "bundle-structure.html"], ["Collections & nested packs", "nested-packs.html"]] },
    { title: "Info.plist", links: [
        ["Manifest overview", "info-plist.html"],
        ["Identity & metadata", "manifest-identity.html"],
        ["Template files", "templates.html", templateLinks],
        ["Libraries & assets", "manifest-resources.html"],
        ["Custom controls", "custom-controls.html", controlLinks],
        ["Child slots", "slots.html"],
        ["Support & recovery", "manifest-support.html"]
    ] },
    { title: "Template language", links: [["Values & macros", "template-values.html"], ["Editable content", "editable-text.html"]] },
    { title: "Themes", links: [["Theme values", "theme-controls.html"], ["Theme bundles", "theme-bundles.html"]] },
    { title: "Reference", links: [["API map", "components.html"]] },
    { title: "Planning", links: [["Built-in components", "built-in-components.html"]] }
];

const pageName = value => value.split("#")[0];

const nav = document.querySelector("[data-doc-nav]");
if (nav) {
    const current = window.location.pathname.split("/").pop() || "index.html";
    const currentLocation = `${current}${window.location.hash}`;
    nav.innerHTML = `
        <a class="brand" href="${base}index.html"><img class="brand-mark" src="${base}assets/foundry-icon.png" alt=""><span>Foundry Developer</span></a>
        <input class="search" type="search" placeholder="Search topics" aria-label="Filter documentation">
        <div data-nav-sections></div>`;
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
                    const branchActive = pageName(href) === current || (children || []).some(([, childHref]) => pageName(childHref) === current);
                    return `<li class="${children ? "nav-branch" : ""}"><a ${href === currentLocation || (href === current && !window.location.hash) ? 'aria-current="page"' : ""} href="${base}${href}">${label}</a>${children && (branchActive || normalized) ? `<ul class="nav-children">${children.filter(([child]) => !normalized || child.toLowerCase().includes(normalized)).map(([child, childHref]) => `<li><a ${childHref === currentLocation ? 'aria-current="location"' : ""} href="${base}${childHref}">${child}</a></li>`).join("")}</ul>` : ""}</li>`;
                }).join("")}</ul>
            </section>`).join("") : '<p class="nav-empty">No matching topics.</p>';
    };
    render();
    nav.querySelector(".search").addEventListener("input", event => render(event.target.value));
}

const currentPage = window.location.pathname.split("/").pop() || "index.html";
const breadcrumbParents = {
    "bundle-structure.html": ["Package", "bundle-structure.html"],
    "nested-packs.html": ["Package", "bundle-structure.html"],
    "info-plist.html": ["Info.plist", "info-plist.html"],
    "manifest-identity.html": ["Info.plist", "info-plist.html"],
    "templates.html": ["Info.plist", "info-plist.html"],
    "manifest-resources.html": ["Info.plist", "info-plist.html"],
    "custom-controls.html": ["Info.plist", "info-plist.html"],
    "slots.html": ["Info.plist", "info-plist.html"],
    "manifest-support.html": ["Info.plist", "info-plist.html"],
    "template-values.html": ["Template language", "template-values.html"],
    "editable-text.html": ["Template language", "template-values.html"],
    "theme-controls.html": ["Themes", "theme-controls.html"],
    "theme-bundles.html": ["Themes", "theme-controls.html"],
    "components.html": ["Reference", "components.html"],
    "built-in-components.html": ["Planning", "built-in-components.html"]
};

const breadcrumbs = document.querySelector(".breadcrumbs");
if (breadcrumbs) {
    if (controlLinks.some(([, href]) => href === currentPage)) {
        breadcrumbs.innerHTML = `<a href="${base}index.html">Foundry Developer</a><span>›</span><a href="${base}info-plist.html">Info.plist</a><span>›</span><a href="${base}custom-controls.html">Custom controls</a>`;
    } else if (breadcrumbParents[currentPage]) {
        const [label, href] = breadcrumbParents[currentPage];
        breadcrumbs.innerHTML = `<a href="${base}index.html">Foundry Developer</a><span>›</span><a href="${base}${href}">${label}</a>`;
    }
}

const referenceTypeByPage = {
    "colour.html": "color",
    "icon-control.html": "icon",
    "link-control.html": "link",
    "text-alignment.html": "textAlignment",
    "font-family.html": "fontFamily",
    "font-size.html": "fontSize",
    "line-height.html": "lineHeight"
};
const referenceType = referenceTypeByPage[window.location.pathname.split("/").pop()];
if (referenceType) {
    document.body.dataset.control = referenceType;
    const referenceScript = document.createElement("script");
    referenceScript.src = `${base}control-reference.js`;
    document.head.append(referenceScript);
}

const main = document.querySelector("main");
if (main && currentPage !== "index.html" && currentPage !== "quick-start.html") {
    const headings = [...main.querySelectorAll(":scope > h2")];
    if (headings.length >= 3) {
        const usedIDs = new Set();
        headings.forEach(heading => {
            if (!heading.id) {
                const root = heading.textContent.trim().toLowerCase()
                    .replace(/[^a-z0-9]+/g, "-")
                    .replace(/^-|-$/g, "") || "section";
                let id = root;
                let suffix = 2;
                while (usedIDs.has(id) || document.getElementById(id)) id = `${root}-${suffix++}`;
                heading.id = id;
            }
            usedIDs.add(heading.id);
        });

        const article = document.createElement("article");
        article.className = "doc-article";
        while (main.firstChild) article.append(main.firstChild);

        const toc = document.createElement("aside");
        toc.className = "page-toc";
        toc.setAttribute("aria-label", "On this page");
        toc.innerHTML = `<strong>On this page</strong><ol>${headings.map(heading => `<li><a href="#${heading.id}">${heading.textContent}</a></li>`).join("")}</ol>`;
        main.classList.add("with-page-toc");
        main.append(article, toc);

        if ("IntersectionObserver" in window) {
            const links = new Map([...toc.querySelectorAll("a")].map(link => [link.hash.slice(1), link]));
            const observer = new IntersectionObserver(entries => {
                const visible = entries.filter(entry => entry.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
                if (!visible) return;
                links.forEach(link => link.removeAttribute("aria-current"));
                links.get(visible.target.id)?.setAttribute("aria-current", "location");
            }, { rootMargin: "-12% 0px -76% 0px" });
            headings.forEach(heading => observer.observe(heading));
        }
    }
}
