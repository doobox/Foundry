const commonValueKeys = [
    ["id", "String", "Required", "Stable identifier; starts with a letter and contains letters, numbers, underscores or hyphens."],
    ["title", "String", "Required", "Label displayed in the inspector."],
    ["group", "String", "Required", "Disclosure-section title."],
    ["control", "Dictionary", "Required", "Nested control configuration. Its accepted keys are listed under Control dictionary."],
    ["default", "Matching value", "Required", "Initial stored value; its plist type must match the control."],
    ["responsive", "Boolean", "Required", "Enables breakpoint-specific overrides."],
    ["toolTip", "String", "Default: omitted", "Optional inspector help text."],
    ["subtitles", "String array", "Default: []", "Captions for members of a control array."]
];

const commonPresentationKeys = [
    ["id", "String", "Required", "Stable unique item identifier."],
    ["group", "String", "Required", "Disclosure-section title."],
    ["control", "Dictionary", "Required", "Nested control configuration. Its accepted keys are listed under Control dictionary."],
    ["title", "String", "Default: empty", "Optional for derived controls and divider; supplies the displayed copy for info."],
    ["default", "Value", "Default: empty String", "Ignored by presentation-only and recalculated derived controls."],
    ["responsive", "Boolean", "Default: false", "Derived and presentation-only controls default to non-responsive."]
];

const commonControlKeys = [
    ["count", "Integer", "Default: omitted", "Omit for one control. Use 2…4 for a control array; default must then be an array of exactly count matching values."]
];

const controls = {
    text: { title: "Text", summary: "A native single-line text field.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no implicit value", defaultValue: "Welcome", usage: "{{ control.heading }}", note: "Use text for short labels and values. Use textArea for prose, or %text% for the dedicated canvas-editable text primitive.", validation: ["default must be a String."] },
    textArea: { title: "Text area", summary: "A multi-line editor that preserves authored line breaks in the stored value.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no implicit value", defaultValue: "First paragraph", usage: "{{ control.body }}", note: "The template expression is escaped; it does not turn line breaks into HTML elements automatically.", validation: ["default must be a String."] },
    link: { title: "Link", summary: "A structured destination supporting URLs, plain text, project pages and project resources.", returnType: "Structured link", output: "href String plus .target and .attributes companion Strings", defaultRule: "Required String; empty means no destination, non-empty initializes a URL destination", defaultValue: "", options: [["absoluteURL", "Boolean", "Default: false", "Prefixes internal paths with the project Site URL when it is a valid HTTP(S) URL; otherwise retains the relative path."]], usage: "<a href=\"{{ control.destination }}\" target=\"{{ control.destination.target }}\" {{ control.destination.attributes }}>Read more</a>", validation: ["default must be a String.", "Custom attribute names that are not valid HTML attribute names are omitted during rendering.", "Opening a new window emits _blank and adds rel=\"noopener noreferrer\" unless the author supplies rel."], note: "Page and resource choices are stored by stable UUID and resolve using their current exported paths." },
    number: { title: "Number", summary: "A numeric text field with bounds, increments and a displayed unit.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "Required Number; no implicit value", defaultValue: 24, options: [["minimum", "Number", "Default: -10000", "Lower editor bound."], ["maximum", "Number", "Default: 10000", "Upper editor bound."], ["step", "Number", "Default: 1", "Editor increment."], ["unit", "String", "Default: empty", "Displayed beside the value; not appended to template output."]], extra: "<key>minimum</key><real>0</real>\n            <key>maximum</key><real>100</real>\n            <key>step</key><real>1</real>\n            <key>unit</key><string>px</string>", usage: "padding: {{ control.spacing }}px;", validation: ["default must be numeric.", "default cannot be below an explicitly declared minimum or above an explicitly declared maximum."] },
    slider: { title: "Slider", summary: "A numeric slider with optional exact tick marks.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "Required Number; no implicit value", defaultValue: 50, options: [["minimum", "Number", "Default: 0", "Lower slider bound."], ["maximum", "Number", "Default: 100", "Upper slider bound."], ["step", "Number", "Default: 1", "Value increment."], ["tickMarks", "Integer", "Default: 0", "Exact number of visible ticks; zero hides ticks."], ["restrictsToTickMarks", "Boolean", "Default: false", "Constrains selection to tick values."]], extra: "<key>minimum</key><real>0</real>\n            <key>maximum</key><real>100</real>\n            <key>step</key><real>10</real>\n            <key>tickMarks</key><integer>11</integer>\n            <key>restrictsToTickMarks</key><true/>", usage: "opacity: calc({{ control.opacity }} / 100);", validation: ["default must be numeric.", "default cannot be outside explicitly declared minimum and maximum values."] },
    date: { title: "Date", summary: "A native date picker storing an ISO-8601 date String.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no generated date", defaultValue: "2026-08-30T00:00:00Z", usage: "<time datetime=\"{{ control.published }}\">{{ control.published }}</time>", validation: ["default must be a String.", "The current manifest validator does not reject malformed ISO-8601 text; developers should supply a valid ISO-8601 default."] },
    color: { title: "Colour", summary: "A custom or theme-aware colour with optional colour adjustment and opacity.", returnType: "Resolved CSS colour String", output: "Hex colour or rgb(… / alpha) String", defaultRule: "Required String: custom, or a known theme role when themeValues is true", defaultValue: "custom", options: [["themeValues", "Boolean", "Default: false", "Offers the theme roles background, surface, text and accent."], ["colorMath", "Boolean", "Default: false", "Adds a −100…100 lighter/darker adjustment; its initial value is 0."], ["opacity", "Boolean", "Default: false", "Adds opacity from 0…1; its initial value is 1."], ["customColor", "String", "Default: #000000", "Initial custom colour; exactly six hexadecimal digits."]], usage: "color: {{ control.textColor }};", validation: ["default must be custom unless themeValues is enabled and the value is a known theme role.", "customColor, when supplied, must be # followed by six hexadecimal digits.", "Literal #RRGGBB or #RRGGBBAA defaults are accepted only for members of a control array."], note: "The resolved template value already incorporates lighter/darker adjustment and opacity." },
    select: { title: "Select", summary: "A popup containing developer-declared titled values.", returnType: "String", output: "HTML-escaped selected option value", defaultRule: "Required String matching one option value", defaultValue: "center", options: [["options", "Array of dictionaries", "Effectively required", "Each dictionary requires String value and title keys. With no matching option the property fails validation."]], extra: "<key>options</key>\n            <array>\n                <dict><key>value</key><string>left</string><key>title</key><string>Left</string></dict>\n                <dict><key>value</key><string>center</string><key>title</key><string>Centre</string></dict>\n            </array>", usage: "text-align: {{ control.alignment }};", validation: ["default must be a String equal to one declared option value."] },
    toggle: { title: "Toggle", summary: "A Boolean switch.", returnType: "Boolean", output: "true or false", defaultRule: "Required Boolean; no implicit value", defaultValue: false, usage: "{% if property.featured %}featured{% endif %}", validation: ["default must be a Boolean."] },
    details: { title: "Details", summary: "A compact titleless Boolean details button.", returnType: "Boolean", output: "true or false", defaultRule: "Required Boolean; no implicit value", defaultValue: false, usage: "{% if property.advanced %}advanced{% endif %}", note: "Supply toolTip on the property because this control deliberately has no visible title.", validation: ["default must be a Boolean."] },
    button: { title: "Button", summary: "A persistent push button backed by Boolean state and optional mapped outputs.", returnType: "Boolean or the plist type supplied by trueValue/falseValue", output: "Mapped value rendered as String, Number or true/false", defaultRule: "Required Boolean state; no implicit value", defaultValue: false, options: [["systemImage", "String", "Default: omitted", "Optional SF Symbol name."], ["trueValue", "String, Number, Boolean or array", "Default: true", "Template output while state is true."], ["falseValue", "String, Number, Boolean or array", "Default: false", "Template output while state is false."]], extra: "<key>systemImage</key><string>bolt.fill</string>\n            <key>trueValue</key><string>active</string>\n            <key>falseValue</key><string>idle</string>", usage: "data-state=\"{{ control.state }}\"", validation: ["default must be a Boolean."] },
    image: { title: "Image", summary: "A picker for an asset in the current Foundry project.", returnType: "String (stored internally as URL value)", output: "HTML-escaped asset reference String", defaultRule: "Required String; empty means no selected asset", defaultValue: "", usage: "<img src=\"{{ control.picture }}\" alt=\"\">", validation: ["default must be a String."], note: "Use imageTransform when the template needs a derived data URL with sizing or visual transformations." },
    imageTransform: { title: "Image transform", summary: "A virtual control deriving an SVG data URL from an image property.", returnType: "String", output: "Percent-encoded data:image/svg+xml URL, or empty String without an input image", defaultRule: "default may be omitted and is ignored; output is recalculated", virtual: true, options: [["input", "String", "Required", "ID of the source image control."], ["scaleMode", "Integer", "Default: 0", "0 fit, 1 fill, 2 stretch, 3 centre."], ["scale", "Number", "Default: 100", "Percentage scale, clamped to at least 0."], ["maxWidth", "Number", "Default: 320", "Output width, clamped to at least 1."], ["maxHeight", "Number", "Default: maxWidth", "Output height, clamped to at least 1."], ["rotation", "Number", "Default: 0", "Degrees around the output centre."], ["borderWidth", "Number", "Default: 0", "Non-negative border width."], ["borderColor", "String", "Default: #000000", "SVG stroke colour."], ["shadowColor", "String", "Default: #000000", "Drop-shadow colour."], ["shadowOpacity", "Number", "Default: 0", "Clamped to 0…1."], ["shadowBlur", "Number", "Default: 0", "Non-negative blur."], ["shadowOffsetX / shadowOffsetY", "Number", "Default: 0", "Drop-shadow offsets."]], extra: "<key>input</key><string>picture</string>\n            <key>scaleMode</key><integer>1</integer>\n            <key>maxWidth</key><real>320</real>\n            <key>maxHeight</key><real>180</real>", usage: "<img src=\"{{ control.thumbnail }}\" alt=\"\">", validation: ["input is required and cannot be empty.", "The current validator does not verify that input names an existing image control."] },
    math: { title: "Math", summary: "A virtual numeric result calculated from constants or other controls.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "default may be omitted and is ignored; output is recalculated", virtual: true, options: [["argument1", "Number or String", "Required", "Numeric constant, numeric String, or another control ID."], ["argument2", "Number or String", "Required", "Numeric constant, numeric String, or another control ID."], ["operation", "String", "Required", "+, −, ×, ÷, remainder, min or max using +, -, *, /, %, min, max."], ["round", "Boolean", "Default: true", "Rounds the calculated result."]], extra: "<key>argument1</key><string>width</string>\n            <key>argument2</key><real>2</real>\n            <key>operation</key><string>*</string>\n            <key>round</key><false/>", usage: "width: {{ control.doubleWidth }}px;", validation: ["argument1, argument2 and a supported operation are required.", "Division or remainder by zero returns 0.", "An unresolved argument leaves the derived value unresolved."] },
    textAlignment: { title: "Text alignment", summary: "A segmented control producing logical CSS alignment values.", returnType: "String", output: "start, center, end or justify", defaultRule: "Required String matching one supported value", defaultValue: "start", usage: "text-align: {{ control.alignment }};", validation: ["default must be start, center, end or justify."] },
    fontFamily: { title: "Font family", summary: "A custom or theme-aware font-family choice.", returnType: "String", output: "Resolved CSS font-family String", defaultRule: "Required String: custom, or a known theme font role when themeValues is true", defaultValue: "custom", options: [["themeValues", "Boolean", "Default: false", "Offers known theme font roles in addition to Custom."]], usage: "font-family: {{ control.typeface }};", validation: ["default must be custom unless themeValues is enabled and it matches a known theme font role."], note: "The hidden custom value starts as system-ui when Custom is selected." },
    fontSize: { title: "Font size", summary: "A custom or theme-aware CSS font-size choice.", returnType: "String", output: "Resolved CSS size String", defaultRule: "Required String: custom, or a known theme size ID when themeValues is true", defaultValue: "custom", options: [["themeValues", "Boolean", "Default: false", "Offers known theme type-scale sizes in addition to Custom."]], usage: "font-size: {{ control.textSize }};", validation: ["default must be custom unless themeValues is enabled and it matches a known theme size ID."], note: "The hidden custom value starts as 1rem when Custom is selected." },
    info: { title: "Info", summary: "Presentation-only explanatory text in an inspector group.", returnType: "None", output: "No template value", defaultRule: "default may be omitted; omitted value is an ignored empty String", virtual: true, usage: "No template value", validation: ["No value validation is performed."], note: "Use title for the explanatory copy. An empty title causes the row to be hidden." },
    divider: { title: "Divider", summary: "A presentation-only visual separator between inspector controls.", returnType: "None", output: "No template value", defaultRule: "default may be omitted; omitted value is an ignored empty String", virtual: true, usage: "No template value", validation: ["No value validation is performed."], note: "Only id, group and control are needed. It has no author-editable state." }
};

const escapeHTML = value => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const type = document.body.dataset.control;
const control = controls[type];
const propertyID = ({ text: "heading", textArea: "body", link: "destination", number: "spacing", slider: "opacity", date: "published", color: "textColor", select: "alignment", toggle: "featured", details: "advanced", button: "state", image: "picture", imageTransform: "thumbnail", math: "doubleWidth", textAlignment: "alignment", fontFamily: "typeface", fontSize: "textSize", info: "guidance", divider: "separator" })[type];

const slug = value => value.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replaceAll(/^-|-$/g, "");

const relatedControls = {
    text: [["Text area", "text-area-control.html"], ["Editable text", "editable-text.html"]],
    textArea: [["Text", "text-control.html"], ["Editable text", "editable-text.html"]],
    link: [["Text", "text-control.html"], ["Image", "image-control.html"]],
    number: [["Slider", "slider-control.html"], ["Math", "math-control.html"]],
    slider: [["Number", "number-control.html"], ["Math", "math-control.html"]],
    color: [["Control arrays", "control-arrays.html"], ["Theme values", "theme-controls.html"]],
    image: [["Image transform", "image-transform-control.html"], ["Link", "link-control.html"]],
    imageTransform: [["Image", "image-control.html"], ["Math", "math-control.html"]],
    fontFamily: [["Font size", "font-size.html"], ["Theme values", "theme-controls.html"]],
    fontSize: [["Font family", "font-family.html"], ["Theme values", "theme-controls.html"]],
    textAlignment: [["Select", "select-control.html"], ["Theme values", "theme-controls.html"]]
};

const implementationGuidance = {
    slider: `<h3>Choosing ticks</h3><p><code>tickMarks</code> is the exact number of marks, including both endpoints. For a 0–100 percentage slider in increments of 10, use 11 marks. Set <code>restrictsToTickMarks</code> to <code>true</code> when intermediate values must not be selectable.</p><pre><code>&lt;key&gt;minimum&lt;/key&gt;&lt;real&gt;0&lt;/real&gt;
&lt;key&gt;maximum&lt;/key&gt;&lt;real&gt;100&lt;/real&gt;
&lt;key&gt;step&lt;/key&gt;&lt;real&gt;10&lt;/real&gt;
&lt;key&gt;tickMarks&lt;/key&gt;&lt;integer&gt;11&lt;/integer&gt;
&lt;key&gt;restrictsToTickMarks&lt;/key&gt;&lt;true/&gt;</code></pre>`,
    details: `<h3>Labelling the titleless button</h3><p>The control intentionally has no visible row title. Put its explanation in the property-level <code>toolTip</code>.</p><pre><code>&lt;key&gt;toolTip&lt;/key&gt;
&lt;string&gt;Show advanced settings&lt;/string&gt;</code></pre>`,
    link: `<h3>Companion template values</h3><p>The base expression returns the resolved <code>href</code>. Foundry also exposes <code>.target</code> and <code>.attributes</code>, so the author’s new-window choice and validated custom attributes reach the element.</p><pre><code>&lt;a href="{{ control.destination }}"
   target="{{ control.destination.target }}"
   {{ control.destination.attributes }}&gt;Read more&lt;/a&gt;</code></pre>`,
    color: `<h3>Theme and custom values</h3><p>With <code>themeValues</code> omitted, the author receives only the custom colour well. Enable it to offer theme roles. Colour math and opacity are independent opt-ins and are already included in the final template value.</p>`,
    select: `<h3>Option values versus titles</h3><p><code>title</code> is what the author sees. <code>value</code> is what templates receive. Keep values stable so changing an author-facing title does not change rendered output.</p>`,
    button: `<h3>Stored state and returned output</h3><p>The inspector stores Boolean button state. Templates receive <code>trueValue</code> or <code>falseValue</code> when those mappings are supplied; otherwise they receive <code>true</code> or <code>false</code>.</p>`,
    imageTransform: `<h3>Derived output</h3><p>This control has no inspector row. It reads the current source image, builds an SVG rendition using the declared transformation options, and returns a data URL suitable for <code>src</code>.</p>`,
    math: `<h3>Referencing another control</h3><p>An argument can be a number or the ID of another numeric property. Foundry resolves dependent math controls repeatedly, allowing one derived value to feed another.</p>`,
    info: `<h3>Supplying the message</h3><p>Use the item’s <code>title</code> as the explanatory text. If title is omitted or empty, Foundry hides the info row.</p><pre><code>&lt;key&gt;title&lt;/key&gt;
&lt;string&gt;Changes here affect every breakpoint.&lt;/string&gt;</code></pre>`
};

function defaultMarkup(value) {
    if (typeof value === "boolean") return `<${value ? "true" : "false"}/>`;
    if (typeof value === "number") return `<real>${value}</real>`;
    return `<string>${value ?? ""}</string>`;
}

function declaration() {
    const title = control.virtual && type !== "info" ? "" : `\n        <key>title</key><string>${type === "info" ? "Changes here affect every breakpoint." : control.title}</string>`;
    const defaults = control.virtual ? "" : `\n        <key>default</key>${defaultMarkup(control.defaultValue)}\n        <key>responsive</key><false/>`;
    const extra = control.extra ? `\n            ${control.extra.replaceAll("\n", "\n            ")}` : "";
    return `<dict>\n        <key>id</key><string>${propertyID}</string>${title}\n        <key>group</key><string>${control.virtual ? "Derived values" : "Content"}</string>\n        <key>control</key>\n        <dict>\n            <key>type</key><string>${type}</string>${extra}\n        </dict>${defaults}\n    </dict>`;
}

function keyReference(item) {
    const [key, kind, requirement, meaning] = item;
    return `<section class="key-reference" id="${slug(key)}"><h3><code>${key}</code></h3><div class="key-meta"><span>${kind}</span><strong>${requirement}</strong></div><p>${meaning}</p></section>`;
}

function renderPage(page) {
    const propertyKeys = control.virtual ? commonPresentationKeys : commonValueKeys;
    const controlKeys = [["type", "String", `Required: ${type}`, `Selects the ${type} control.`], ...(control.virtual ? [] : commonControlKeys), ...(control.options || [])];
    const sections = [
        ["quick-start", "Quick start"],
        ["how-it-works", "How it works"],
        ["property-dictionary", "Property dictionary"],
        ["control-dictionary", "Control dictionary"],
        ["return-value", "Return value"],
        ["complete-example", "Complete example"],
        ["validation", "Validation and behaviour"],
        ["related", "Related documentation"]
    ];
    const inspectorKind = control.virtual ? (type === "info" || type === "divider" ? "Presentation only" : "No — derived value") : "Visible control";
    const note = control.note ? `<div class="note"><strong>Important:</strong> ${control.note}</div>` : "";
    const guidance = implementationGuidance[type] || "";
    const related = relatedControls[type] || [["All custom controls", "custom-controls.html"], ["Template values", "template-values.html"]];
    const fullPlist = `<key>customItems</key>\n<array>\n    ${declaration().replaceAll("\n", "\n    ")}\n</array>`;

    page.innerHTML = `<div class="reference-layout"><article class="reference-article"><div class="breadcrumbs"><a href="index.html">Foundry Developer</a><span>›</span><a href="custom-controls.html">Custom controls</a><span>›</span>${control.title}</div><p class="eyebrow">Control reference</p><h1>${control.title} <code class="title-code">${type}</code></h1><p class="lede">${control.summary}</p><div class="api-facts"><div><span>Stored value</span><strong>${control.returnType}</strong></div><div><span>Template output</span><strong>${control.output}</strong></div><div><span>Default contract</span><strong>${control.defaultRule}</strong></div><div><span>Inspector</span><strong>${inspectorKind}</strong></div></div>
    <section id="quick-start"><h2>Quick start</h2><p>Add this dictionary to the component’s <code>customItems</code> array. This is the smallest useful declaration for the example on this page.</p><pre><code>${escapeHTML(declaration())}</code></pre></section>
    <section id="how-it-works"><h2>How it works</h2><ol class="flow-list"><li>Foundry decodes the property from <code>customItems</code> and creates ${control.virtual ? "its derived or presentation behaviour" : "the inspector control"}.</li><li>${control.virtual ? "Foundry calculates or presents it without storing an author-edited control value." : `The author’s value is stored under <code>${propertyID}</code>.`}</li><li>${control.returnType === "None" ? "This control intentionally produces no template value." : `Templates read the resolved value with <code>{{ control.${propertyID} }}</code> or <code>{{ property.${propertyID} }}</code>.`}</li></ol>${guidance}${note}</section>
    <section id="property-dictionary"><h2>Property dictionary</h2><p>These keys sit beside <code>control</code> in the item inside <code>customItems</code>. They describe the property, its inspector placement and its stored default.</p>${propertyKeys.map(keyReference).join("")}</section>
    <section id="control-dictionary"><h2>Control dictionary</h2><p>Only the keys listed here are meaningful for <code>${type}</code>. Omitted optional keys use the defaults shown.</p>${controlKeys.map(keyReference).join("")}${control.options?.length ? "" : `<div class="note"><strong>No control-specific options.</strong> Apart from the shared keys above, <code>${type}</code> does not read additional control dictionary keys.</div>`}</section>
    <section id="return-value"><h2>Return value</h2><p><code>{{ control.${propertyID} }}</code> resolves as <strong>${control.output}</strong>. Stored internally, its value is <strong>${control.returnType}</strong>.</p><pre><code>${escapeHTML(control.usage)}</code></pre></section>
    <section id="complete-example"><h2>Complete example</h2><h3>Info.plist</h3><pre><code>${escapeHTML(fullPlist)}</code></pre><h3>Use it in a template</h3><pre><code>${escapeHTML(control.usage)}</code></pre></section>
    <section id="validation"><h2>Validation and behaviour</h2><ul class="rule-list">${control.validation.map(rule => `<li>${rule}</li>`).join("")}<li>Property IDs must be unique, start with a letter, and contain only letters, numbers, underscores or hyphens.</li></ul></section>
    <section id="related"><h2>Related documentation</h2><div class="page-links">${related.map(([title, href]) => `<a class="card" href="${href}"><strong>${title}</strong><p>Continue with the related API and implementation guidance.</p></a>`).join("")}</div></section><p class="control-footer"><a href="custom-controls.html">← All custom controls</a></p></article><aside class="page-toc" aria-label="On this page"><strong>On this page</strong><ol>${sections.map(([id, title]) => `<li><a href="#${id}">${title}</a></li>`).join("")}</ol></aside></div>`;
}

const page = document.querySelector("main");
if (page && control) renderPage(page);
