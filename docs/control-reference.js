const commonValueKeys = [
    ["id", "String", "Required", "Stable identifier; starts with a letter and contains letters, numbers, underscores or hyphens."],
    ["labels", "String or String array", "Default: empty", "Inspector label for one control. When count is present, an array containing one non-empty label per control is required."],
    ["group", "String", "Default: Settings", "Optional disclosure-section title. Omit it to place the control in Settings."],
    ["toolTip", "String", "Default: omitted", "Optional inspector help text."],
    ["subtitles", "String array", "Default: []", "Optional secondary captions for members of a control array; the array cannot be longer than count."]
];

const commonPresentationKeys = [
    ["id", "String", "Required", "Stable unique item identifier."],
    ["group", "String", "Default: Settings", "Optional disclosure-section title. Omit it to place the control in Settings."],
    ["labels", "String", "Default: empty", "Optional for derived controls and divider; supplies the displayed copy for info."],
    ["default", "Value", "Default: empty String", "Ignored by presentation-only and recalculated derived controls."],
    ["responsive", "Boolean", "Default: false", "Derived and presentation-only controls default to non-responsive."]
];

const commonControlKeys = [
    ["count", "Integer", "Default: omitted", "Omit for one control. Use 2…4 for a control array; labels and default must then be arrays containing exactly count entries, and every label must be non-empty."]
];

const controls = {
    text: { title: "Text", summary: "A native single-line text field.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no implicit value", defaultValue: "Welcome", usage: "{{ control.heading }}", note: "Use text for short labels and values. Use textArea for prose, or %text% for the dedicated canvas-editable text primitive.", validation: ["default must be a String."] },
    textArea: { title: "Text area", summary: "A multi-line editor that preserves authored line breaks in the stored value.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no implicit value", defaultValue: "First paragraph", usage: "{{ control.body }}", note: "The template expression is escaped; it does not turn line breaks into HTML elements automatically.", validation: ["default must be a String."] },
    link: { title: "Link", summary: "A structured destination supporting URLs, plain text, project pages and project resources.", returnType: "Structured link", output: "href String plus .target and .attributes companion Strings", defaultRule: "Required String; empty means no destination, non-empty initializes a URL destination", defaultValue: "", options: [["absoluteURL", "Boolean", "Default: false", "Prefixes internal paths with the project Site URL when it is a valid HTTP(S) URL; otherwise retains the relative path."]], usage: "<a href=\"{{ control.destination }}\" target=\"{{ control.destination.target }}\" {{ control.destination.attributes }}>Read more</a>", validation: ["default must be a String.", "Custom attribute names that are not valid HTML attribute names are omitted during rendering.", "Opening a new window emits _blank and adds rel=\"noopener noreferrer\" unless the author supplies rel."], note: "Page and resource choices are stored by stable UUID and resolve using their current exported paths." },
    number: { title: "Number", summary: "A numeric text field with bounds, increments and an optional displayed unit.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "Required Number; no implicit value", defaultValue: 24, options: [["minimum", "Number", "Default: -10000", "Lower editor bound."], ["maximum", "Number", "Default: 10000", "Upper editor bound."], ["step", "Number", "Default: 1", "Editor increment."], ["unit", "String", "Default: none", "Optional label displayed beside the value. It may contain at most three characters and is not appended to template output."]], extra: "<key>minimum</key><real>0</real>\n            <key>maximum</key><real>100</real>\n            <key>step</key><real>1</real>\n            <key>unit</key><string>px</string>", usage: "padding: {{ control.spacing }}px;", validation: ["default must be numeric.", "default cannot be below an explicitly declared minimum or above an explicitly declared maximum.", "unit is optional and cannot contain more than three characters."] },
    slider: { title: "Slider", summary: "A continuous or stepped numeric slider with optional visual tick marks and an exact-value field.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "Optional Number; default is zero clamped into the declared range", defaultValue: 50, options: [["minimum", "Number", "Default: 0", "Lower slider bound."], ["maximum", "Number", "Default: 100", "Upper slider bound."], ["step", "Number", "Default: 0", "Selectable increment relative to minimum. Zero means continuous."], ["ticks", "Integer", "Default: 0", "Exact number of evenly distributed visible marks, including both endpoints. Ticks are visual only."], ["showsValueField", "Boolean", "Default: true", "Shows an editable number field for precise entry beside the slider."], ["unit", "String", "Default: none", "Optional label displayed beside each value field. It may contain at most three characters and is not appended to template output."]], extra: "<key>minimum</key><real>0</real>\n            <key>maximum</key><real>100</real>\n            <key>step</key><real>10</real>\n            <key>ticks</key><integer>11</integer>\n            <key>showsValueField</key><true/>\n            <key>unit</key><string>%</string>", usage: "filter: brightness({{ control.intensity }}%);", validation: ["An omitted default becomes zero when zero is in range, otherwise the nearest bound.", "An explicit default must be numeric and within the declared range.", "Directly entered values are clamped to the range and snap to a positive step.", "maximum must be greater than minimum.", "step cannot be negative; zero means continuous.", "ticks must be zero or at least two.", "unit is optional and cannot contain more than three characters."] },
    date: { title: "Date", summary: "A native date picker storing an ISO-8601 date String.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no generated date", defaultValue: "2026-08-30T00:00:00Z", usage: "<time datetime=\"{{ control.published }}\">{{ control.published }}</time>", validation: ["default must be a String.", "The current manifest validator does not reject malformed ISO-8601 text; developers should supply a valid ISO-8601 default."] },
    color: { title: "Colour", summary: "A custom or theme-aware colour with optional colour adjustment and opacity.", returnType: "Resolved CSS colour String", output: "Hex colour or rgb(… / alpha) String", defaultRule: "Required String: custom, or a known theme role when themeValues is true", defaultValue: "custom", options: [["themeValues", "Boolean", "Default: false", "Offers the theme roles background, surface, text and accent."], ["colorMath", "Boolean", "Default: false", "Adds a −100…100 lighter/darker adjustment; its initial value is 0."], ["opacity", "Boolean", "Default: false", "Adds opacity from 0…1; its initial value is 1."], ["customColor", "String", "Default: #000000", "Initial custom colour; exactly six hexadecimal digits."]], usage: "color: {{ control.textColor }};", validation: ["default must be custom unless themeValues is enabled and the value is a known theme role.", "customColor, when supplied, must be # followed by six hexadecimal digits.", "Literal #RRGGBB or #RRGGBBAA defaults are accepted only for members of a control array."], note: "The resolved template value already incorporates lighter/darker adjustment and opacity." },
    select: { title: "Select", summary: "A popup containing developer-declared titled values.", returnType: "String", output: "HTML-escaped selected option value", defaultRule: "Required String matching one option value", defaultValue: "center", options: [["options", "Array of dictionaries", "Effectively required", "Each dictionary requires String value and title keys. With no matching option the property fails validation."]], extra: "<key>options</key>\n            <array>\n                <dict><key>value</key><string>left</string><key>title</key><string>Left</string></dict>\n                <dict><key>value</key><string>center</string><key>title</key><string>Centre</string></dict>\n            </array>", usage: "text-align: {{ control.alignment }};", validation: ["default must be a String equal to one declared option value."] },
    toggle: { title: "Toggle", summary: "A Boolean switch.", returnType: "Boolean", output: "true or false", defaultRule: "Required Boolean; no implicit value", defaultValue: false, usage: "{% if property.featured %}featured{% endif %}", validation: ["default must be a Boolean."] },
    details: { title: "Details", summary: "A compact labelless Boolean details button.", returnType: "Boolean", output: "true or false", defaultRule: "Required Boolean; no implicit value", defaultValue: false, usage: "{% if property.advanced %}advanced{% endif %}", note: "Supply toolTip on the property because this control deliberately has no visible label.", validation: ["default must be a Boolean."] },
    button: { title: "Button", summary: "A persistent push button backed by Boolean state and optional mapped outputs.", returnType: "Boolean or the plist type supplied by trueValue/falseValue", output: "Mapped value rendered as String, Number or true/false", defaultRule: "Required Boolean state; no implicit value", defaultValue: false, options: [["systemImage", "String", "Default: omitted", "Optional SF Symbol name."], ["trueValue", "String, Number, Boolean or array", "Default: true", "Template output while state is true."], ["falseValue", "String, Number, Boolean or array", "Default: false", "Template output while state is false."]], extra: "<key>systemImage</key><string>bolt.fill</string>\n            <key>trueValue</key><string>active</string>\n            <key>falseValue</key><string>idle</string>", usage: "data-state=\"{{ control.state }}\"", validation: ["default must be a Boolean."] },
    math: { title: "Math", summary: "A virtual numeric result calculated from constants or other controls.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "default may be omitted and is ignored; output is recalculated", virtual: true, options: [["argument1", "Number or String", "Required", "Numeric constant, numeric String, or another control ID."], ["argument2", "Number or String", "Required", "Numeric constant, numeric String, or another control ID."], ["operation", "String", "Required", "+, −, ×, ÷, remainder, min or max using +, -, *, /, %, min, max."], ["round", "Boolean", "Default: true", "Rounds the calculated result."]], extra: "<key>argument1</key><string>width</string>\n            <key>argument2</key><real>2</real>\n            <key>operation</key><string>*</string>\n            <key>round</key><false/>", usage: "width: {{ control.doubleWidth }}px;", validation: ["argument1, argument2 and a supported operation are required.", "Division or remainder by zero returns 0.", "An unresolved argument leaves the derived value unresolved."] },
    textAlignment: { title: "Text alignment", summary: "A segmented control producing logical CSS alignment values.", returnType: "String", output: "start, center, end or justify", defaultRule: "Required String matching one supported value", defaultValue: "start", usage: "text-align: {{ control.alignment }};", validation: ["default must be start, center, end or justify."] },
    fontFamily: { title: "Font family", summary: "A theme font-family choice configured by the project author.", returnType: "String", output: "Resolved CSS font-family String", defaultRule: "Required String: body, heading or monospaced", defaultValue: "body", options: [], usage: "font-family: {{ control.typeface }};", validation: ["default must be body, heading or monospaced."], note: "The inspector also offers additional fonts added in the project Theme Editor. Font families cannot be entered directly in a component inspector." },
    fontSize: { title: "Font size", summary: "A custom or theme-aware CSS font-size choice.", returnType: "String", output: "Resolved CSS size String", defaultRule: "Required String: custom, or a known theme size ID when themeValues is true", defaultValue: "custom", options: [["themeValues", "Boolean", "Default: false", "Offers known theme type-scale sizes in addition to Custom."]], usage: "font-size: {{ control.textSize }};", validation: ["default must be custom unless themeValues is enabled and it matches a known theme size ID."], note: "The hidden custom value starts as 1rem when Custom is selected." },
    lineHeight: { title: "Line height", summary: "A theme-aware line-height choice that emits an explicit component-level CSS value.", returnType: "String", output: "CSS line-height number or theme CSS variable", defaultRule: "Required String matching theme, none, tight, snug, normal, relaxed or loose", defaultValue: "theme", options: [["fontSize", "String", "Default: omitted", "ID of the fontSize control whose theme line height should be used. Without it, Theme uses the base theme size."]], extra: "<key>fontSize</key><string>textSize</string>", usage: "line-height: {{ control.lineHeight }};", validation: ["default must be theme, none, tight, snug, normal, relaxed or loose.", "fontSize, when supplied, must identify a declared fontSize control."], note: "Even Theme resolves into an explicit CSS value, so the component declaration overrides inherited body line height." },
    info: { title: "Info", summary: "Presentation-only explanatory text in an inspector group.", returnType: "None", output: "No template value", defaultRule: "default may be omitted; omitted value is an ignored empty String", virtual: true, usage: "No template value", validation: ["No value validation is performed."], note: "Use labels for the explanatory copy. An empty label causes the row to be hidden." },
    divider: { title: "Divider", summary: "A presentation-only visual separator between inspector controls.", returnType: "None", output: "No template value", defaultRule: "default may be omitted; omitted value is an ignored empty String", virtual: true, usage: "No template value", validation: ["No value validation is performed."], note: "Only id, group and type are needed. It has no author-editable state." }
};

const escapeHTML = value => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const type = document.body.dataset.control;
const control = controls[type];
const propertyID = ({ text: "heading", textArea: "body", link: "destination", number: "spacing", slider: "intensity", date: "published", color: "textColor", select: "alignment", toggle: "featured", details: "advanced", button: "state", math: "doubleWidth", textAlignment: "alignment", fontFamily: "typeface", fontSize: "textSize", lineHeight: "lineHeight", info: "guidance", divider: "separator" })[type];

const slug = value => value.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replaceAll(/^-|-$/g, "");

const relatedControls = {
    text: [["Text area", "text-area-control.html"], ["Editable text", "editable-text.html"]],
    textArea: [["Text", "text-control.html"], ["Editable text", "editable-text.html"]],
    link: [["Text", "text-control.html"], ["Button", "button-control.html"]],
    number: [["Slider", "slider-control.html"], ["Math", "math-control.html"]],
    slider: [["Number", "number-control.html"], ["Math", "math-control.html"]],
    color: [["Control arrays", "control-arrays.html"], ["Theme values", "theme-controls.html"]],
    fontFamily: [["Font size", "font-size.html"], ["Theme values", "theme-controls.html"]],
    fontSize: [["Font family", "font-family.html"], ["Theme values", "theme-controls.html"]],
    lineHeight: [["Font size", "font-size.html"], ["Theme values", "theme-controls.html"]],
    textAlignment: [["Select", "select-control.html"], ["Theme values", "theme-controls.html"]]
};

const implementationGuidance = {
    slider: `<h3>Steps and ticks are independent</h3><p><code>step</code> controls selectable values and is measured from <code>minimum</code>. Omit it or use zero for a continuous slider. <code>ticks</code> is purely visual and gives the exact number of marks, including both endpoints. For a 0–100 percentage slider in increments of 10, use a step of 10 and 11 marks.</p><pre><code>&lt;key&gt;minimum&lt;/key&gt;&lt;real&gt;0&lt;/real&gt;
&lt;key&gt;maximum&lt;/key&gt;&lt;real&gt;100&lt;/real&gt;
&lt;key&gt;step&lt;/key&gt;&lt;real&gt;10&lt;/real&gt;
&lt;key&gt;ticks&lt;/key&gt;&lt;integer&gt;11&lt;/integer&gt;</code></pre><p>For a 0–1000 integer slider without marks, use <code>step</code> 1 and omit <code>ticks</code>.</p>`,
    details: `<h3>Describing the labelless button</h3><p>The control intentionally has no visible row label. Put its explanation in the property-level <code>toolTip</code>.</p><pre><code>&lt;key&gt;toolTip&lt;/key&gt;
&lt;string&gt;Show advanced settings&lt;/string&gt;</code></pre>`,
    link: `<h3>Companion template values</h3><p>The base expression returns the resolved <code>href</code>. Foundry also exposes <code>.target</code> and <code>.attributes</code>, so the author’s new-window choice and validated custom attributes reach the element.</p><pre><code>&lt;a href="{{ control.destination }}"
   target="{{ control.destination.target }}"
   {{ control.destination.attributes }}&gt;Read more&lt;/a&gt;</code></pre>`,
    color: `<h3>Theme and custom values</h3><p>With <code>themeValues</code> omitted, the author receives only the custom colour well. Enable it to offer theme roles. Colour math and opacity are independent opt-ins and are already included in the final template value.</p>`,
    select: `<h3>Option values versus titles</h3><p><code>title</code> is what the author sees. <code>value</code> is what templates receive. Keep values stable so changing an author-facing title does not change rendered output.</p>`,
    button: `<h3>Stored state and returned output</h3><p>The inspector stores Boolean button state. Templates receive <code>trueValue</code> or <code>falseValue</code> when those mappings are supplied; otherwise they receive <code>true</code> or <code>false</code>.</p>`,
    math: `<h3>Referencing another control</h3><p>An argument can be a number or the ID of another numeric property. Foundry resolves dependent math controls repeatedly, allowing one derived value to feed another.</p>`,
    info: `<h3>Supplying the message</h3><p>Use the item’s <code>labels</code> as the explanatory text. If labels is omitted or empty, Foundry hides the info row.</p><pre><code>&lt;key&gt;labels&lt;/key&gt;
&lt;string&gt;Changes here affect every breakpoint.&lt;/string&gt;</code></pre>`
};

function defaultMarkup(value) {
    if (typeof value === "boolean") return `<${value ? "true" : "false"}/>`;
    if (typeof value === "number") return `<real>${value}</real>`;
    return `<string>${value ?? ""}</string>`;
}

function declaration() {
    const label = control.virtual && type !== "info" ? "" : `\n        <key>labels</key><string>${type === "info" ? "Changes here affect every breakpoint." : control.title}</string>`;
    const defaultValue = type === "slider" ? "" : `\n        <key>default</key>${defaultMarkup(control.defaultValue)}`;
    const defaults = control.virtual ? "" : `${defaultValue}\n        <key>responsive</key><false/>`;
    const extra = control.extra ? `\n        ${control.extra.replaceAll("\n", "\n        ")}` : "";
    return `<dict>\n        <key>id</key><string>${propertyID}</string>${label}\n        <key>group</key><string>${control.virtual ? "Derived values" : "Content"}</string>\n        <key>type</key><string>${type}</string>${extra}${defaults}\n    </dict>`;
}

function keyReference(item) {
    const [key, kind, requirement, meaning] = item;
    const requirementTags = requirement.startsWith("Default:")
        ? `<strong>Optional</strong><span>${requirement}</span>`
        : `<strong>${requirement}</strong>`;
    return `<section class="key-reference" id="${slug(key)}"><h3><code>${key}</code></h3><div class="key-meta"><span>${kind}</span>${requirementTags}</div><p>${meaning}</p></section>`;
}

function renderPage(page) {
    const defaultKey = ["default", "Matching value", type === "slider" ? "Default: zero clamped to range" : "Required", "Initial stored value; its plist type must match the control. Slider is the only visible control with an implicit default."];
    const responsiveKey = ["responsive", "Boolean", "Required", "Enables breakpoint-specific overrides."];
    const propertyKeys = control.virtual ? commonPresentationKeys : [...commonValueKeys, defaultKey, responsiveKey];
    const optionKeys = [["type", "String", `Required: ${type}`, `Selects the ${type} control.`], ...(control.virtual ? [] : commonControlKeys), ...(control.options || [])];
    const sections = [
        ["quick-start", "Quick start"],
        ["how-it-works", "How it works"],
        ["item-keys", "Custom item keys"],
        ["control-options", "Control-specific keys"],
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
    <section id="item-keys"><h2>Custom item keys</h2><p>Each member of <code>customItems</code> is one flat control declaration. These keys identify the property, place it in the inspector and define its stored value.</p>${propertyKeys.map(keyReference).join("")}</section>
    <section id="control-options"><h2>Control-specific keys</h2><p>These keys sit directly in the same custom-item dictionary. Only the keys listed here are meaningful for <code>${type}</code>; omitted optional keys use the defaults shown.</p>${optionKeys.map(keyReference).join("")}${control.options?.length ? "" : `<div class="note"><strong>No additional options.</strong> Apart from <code>type</code> and the shared array key above, <code>${type}</code> reads no control-specific keys.</div>`}</section>
    <section id="return-value"><h2>Return value</h2><p><code>{{ control.${propertyID} }}</code> resolves as <strong>${control.output}</strong>. Stored internally, its value is <strong>${control.returnType}</strong>.</p><pre><code>${escapeHTML(control.usage)}</code></pre></section>
    <section id="complete-example"><h2>Complete example</h2><h3>Info.plist</h3><pre><code>${escapeHTML(fullPlist)}</code></pre><h3>Use it in a template</h3><pre><code>${escapeHTML(control.usage)}</code></pre></section>
    <section id="validation"><h2>Validation and behaviour</h2><ul class="rule-list">${control.validation.map(rule => `<li>${rule}</li>`).join("")}<li>Property IDs must be unique, start with a letter, and contain only letters, numbers, underscores or hyphens.</li></ul></section>
    <section id="related"><h2>Related documentation</h2><div class="page-links">${related.map(([title, href]) => `<a class="card" href="${href}"><strong>${title}</strong><p>Continue with the related API and implementation guidance.</p></a>`).join("")}</div></section><p class="control-footer"><a href="custom-controls.html">← All custom controls</a></p></article><aside class="page-toc" aria-label="On this page"><strong>On this page</strong><ol>${sections.map(([id, title]) => `<li><a href="#${id}">${title}</a></li>`).join("")}</ol></aside></div>`;
}

const page = document.querySelector("main");
if (page && control) renderPage(page);
