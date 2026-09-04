const commonValueKeys = [
    ["id", "String", "Required", "Stable identifier; starts with a letter and contains letters, numbers, underscores or hyphens."],
    ["labels", "String or String array", "Default: empty", "Inspector label for one control. When count is present, an array containing one non-empty label per control is required."],
    ["group", "String", "Default: Settings", "Optional disclosure-section title. Omit it to place the control in Settings."],
    ["toolTip", "String", "Default: omitted", "Optional inspector help text."],
    ["subtitles", "String array", "Default: []", "Optional secondary captions for members of a control array; the array cannot be longer than count."],
    ["enable", "Dictionary", "Default: shown", "Conditionally shows this control using another control’s value. See Conditional visibility for the complete operation reference."]
];

const commonPresentationKeys = [
    ["id", "String", "Required", "Stable unique item identifier."],
    ["group", "String", "Default: Settings", "Optional disclosure-section title. Omit it to place the control in Settings."],
    ["labels", "String", "Default: empty", "Optional for derived controls and divider; supplies the displayed copy for info."],
    ["default", "Value", "Default: empty String", "Ignored by presentation-only and recalculated derived controls."],
    ["responsive", "Boolean", "Default: false", "Derived and presentation-only controls default to non-responsive."],
    ["enable", "Dictionary", "Default: shown", "Conditionally shows this item using another control’s value. See Conditional visibility for the complete operation reference."]
];

const commonControlKeys = [
    ["count", "Integer", "Default: omitted", "Omit for one control. An ordinary Select using only declared options may use 2…4 for a control array. Do not use count when themeValues is present."]
];

const controls = {
    text: { title: "Text", summary: "A native single-line text field.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no implicit value", defaultValue: "Welcome", usage: "{{ control.heading }}", note: "Use text for short named values. Use textArea for prose, or {{ text }} for canvas-editable text at a specific markup position.", validation: ["default must be a String."] },
    textArea: { title: "Text area", summary: "A multi-line editor that preserves authored line breaks in the stored value.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no implicit value", defaultValue: "First paragraph", usage: "{{ control.body }}", note: "The template expression is escaped; it does not turn line breaks into HTML elements automatically.", validation: ["default must be a String."] },
    link: { title: "Link", summary: "A structured destination supporting URLs, plain text, project pages and project resources.", returnType: "Structured link", output: "href String plus .target and .attributes companion Strings", defaultRule: "Required String; empty means no destination, non-empty initializes a URL destination", defaultValue: "", options: [["absoluteURL", "Boolean", "Default: false", "Prefixes internal paths with the project Site URL when it is a valid HTTP(S) URL; otherwise retains the relative path."]], usage: "<a href=\"{{ control.destination }}\" target=\"{{ control.destination.target }}\" {{ control.destination.attributes }}>Read more</a>", validation: ["default must be a String.", "Custom attribute names that are not valid HTML attribute names are omitted during rendering.", "Opening a new window emits _blank and adds rel=\"noopener noreferrer\" unless the author supplies rel."], note: "Page and resource choices are stored by stable UUID and resolve using their current exported paths." },
    number: { title: "Number", summary: "A numeric text field with bounds, increments and an optional displayed unit.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "Required Number; no implicit value", defaultValue: 24, options: [["minimum", "Number", "Default: -10000", "Lower editor bound."], ["maximum", "Number", "Default: 10000", "Upper editor bound."], ["step", "Number", "Default: 1", "Editor increment."], ["units", "String or Array", "Default: none", "Inspector-only unit label. Use a string for one value or one array entry per multi value. Each may contain at most three characters; units are not appended to template output."]], extra: "<key>minimum</key><real>0</real>\n            <key>maximum</key><real>100</real>\n            <key>step</key><real>1</real>\n            <key>units</key><string>px</string>", usage: "padding: {{ control.spacing }}px;", validation: ["default must be numeric.", "default cannot be below an explicitly declared minimum or above an explicitly declared maximum.", "Each unit is optional and cannot contain more than three characters."] },
    padding: { title: "Padding", summary: "A four-sided spacing editor that offers the active theme’s spacing scale and a local custom value for every edge.", returnType: "One structured spacing value", output: "CSS padding shorthand String", defaultRule: "Required four-String array in top, right, bottom, left order", defaultValue: ["lg", "none", "lg", "none"], fixedFour: true, options: [["customValue", "Number array", "Default: [0, 0, 0, 0]", "Initial pixel values used when the matching side is set to Custom, in top, right, bottom, left order."], ["minimum", "Number", "Default: 0", "Lower bound for custom pixel values; cannot be negative."], ["maximum", "Number", "Default: 640", "Upper bound for custom pixel values."], ["step", "Number", "Default: 1", "Increment for custom pixel values."]], extra: "<key>customValue</key>\n            <array><real>64</real><real>0</real><real>64</real><real>0</real></array>\n            <key>minimum</key><real>0</real>\n            <key>maximum</key><real>320</real>\n            <key>step</key><real>4</real>", usage: "padding: {{ control.padding }};", validation: ["default must contain exactly four Strings in top, right, bottom, left order.", "Each default must be none, custom, or a portable theme spacing ID: 3xs, 2xs, xs, sm, md, lg, xl, 2xl or 3xl.", "customValue, when supplied, must contain exactly four non-negative Numbers.", "count and units do not apply; the control always edits all four sides."], note: "Foundry stores all four sources and custom values atomically under this property ID. It does not create hidden companion properties." },
    margin: { title: "Margin", summary: "A four-sided spacing editor for space outside an element, with theme values, local custom values and Auto.", returnType: "One structured spacing value", output: "CSS margin shorthand String", defaultRule: "Required four-String array in top, right, bottom, left order", defaultValue: ["none", "auto", "none", "auto"], fixedFour: true, options: [["customValue", "Number array", "Default: [0, 0, 0, 0]", "Initial pixel values used when the matching side is set to Custom, in top, right, bottom, left order."], ["minimum", "Number", "Default: -640", "Lower bound for custom pixel values; negative margins are allowed."], ["maximum", "Number", "Default: 640", "Upper bound for custom pixel values."], ["step", "Number", "Default: 1", "Increment for custom pixel values."]], extra: "<key>customValue</key>\n            <array><real>0</real><real>0</real><real>0</real><real>0</real></array>\n            <key>minimum</key><real>-320</real>\n            <key>maximum</key><real>320</real>\n            <key>step</key><real>4</real>", usage: "margin: {{ control.margin }};", validation: ["default must contain exactly four Strings in top, right, bottom, left order.", "Each default must be none, custom, auto, or a portable theme spacing ID: 3xs, 2xs, xs, sm, md, lg, xl, 2xl or 3xl.", "customValue, when supplied, must contain exactly four Numbers.", "count and units do not apply; the control always edits all four sides."], note: "Foundry stores all four sources and custom values atomically under this property ID. It does not create hidden companion properties." },
    slider: { title: "Slider", summary: "A continuous or stepped numeric slider with optional visual tick marks and an exact-value field.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "Optional Number; default is zero clamped into the declared range", defaultValue: 50, options: [["minimum", "Number", "Default: 0", "Lower slider bound."], ["maximum", "Number", "Default: 100", "Upper slider bound."], ["step", "Number", "Default: 0", "Selectable increment relative to minimum. Zero means continuous."], ["ticks", "Integer", "Default: 0", "Exact number of evenly distributed visible marks, including both endpoints. Ticks are visual only."], ["showsValueField", "Boolean", "Default: true", "Shows an editable number field for precise entry beside the slider."], ["units", "String or Array", "Default: none", "Inspector-only unit label. Use a string for one slider or one array entry per multi slider. Each may contain at most three characters; units are not appended to template output."]], extra: "<key>minimum</key><real>0</real>\n            <key>maximum</key><real>100</real>\n            <key>step</key><real>10</real>\n            <key>ticks</key><integer>11</integer>\n            <key>showsValueField</key><true/>\n            <key>units</key><string>%</string>", usage: "filter: brightness({{ control.intensity }}%);", validation: ["An omitted default becomes zero when zero is in range, otherwise the nearest bound.", "An explicit default must be numeric and within the declared range.", "Directly entered values are clamped to the range and snap to a positive step.", "maximum must be greater than minimum.", "step cannot be negative; zero means continuous.", "ticks must be zero or at least two.", "Each unit is optional and cannot contain more than three characters."] },
    date: { title: "Date", summary: "A native date picker storing an ISO-8601 date String.", returnType: "String", output: "HTML-escaped String", defaultRule: "Required String; no generated date", defaultValue: "2026-08-30T00:00:00Z", usage: "<time datetime=\"{{ control.published }}\">{{ control.published }}</time>", validation: ["default must be a String.", "The current manifest validator does not reject malformed ISO-8601 text; developers should supply a valid ISO-8601 default."] },
    color: { title: "Colour", summary: "A normal colour picker that can optionally add theme choices above its Custom option.", returnType: "One structured colour value", output: "Resolved theme colour, custom hex colour, or rgb(… / alpha) String", defaultRule: "Required String custom; themeValues supplies the initial theme role when present", defaultValue: "custom", options: [["themeValues", "String", "Default: omitted", "Use background, surface, text, accent or links to add theme choices and initially select that role."], ["colorMath", "Boolean", "Default: false", "Adds a −100…100 lighter/darker adjustment; its initial value is 0."], ["opacity", "Boolean", "Default: false", "Allows alpha in the native custom-colour picker; no separate opacity control is shown and theme colours are unchanged."], ["customColor", "String", "Default: #000000", "Initial value of the underlying normal colour picker; exactly six hexadecimal digits."]], usage: "color: {{ control.textColor }};", validation: ["themeValues must be background, surface, text, accent or links.", "customColor, when supplied, must be # followed by six hexadecimal digits.", "Literal #RRGGBB or #RRGGBBAA defaults are accepted only for members of a control array."], note: "Without themeValues this is the normal colour picker. With themeValues, the declared role is initially selected and the picker remains hidden until Custom is chosen. Foundry stores everything atomically under this property ID." },
    icon: { title: "Icon", summary: "A searchable visual picker containing every icon in Foundry’s built-in icon library.", returnType: "String", output: "HTML-escaped icon name without the bi- prefix", defaultRule: "Required String matching a Foundry icon name", defaultValue: "stars", usage: "<i class=\"bi bi-{{ control.symbol }}\" aria-hidden=\"true\"></i>", validation: ["default must name an icon in Foundry’s built-in icon catalogue.", "The component must request com.foundry.icons major version 1 in its top-level libraries array."], note: "The stored value is the stable icon name, such as stars or rocket-takeoff. Foundry supplies the bi- prefix in your markup, not in the stored value." },
    select: { title: "Select", summary: "A popup containing developer-declared options, values requested from the active theme, or both.", returnType: "String or a theme-specific structured value", output: "Declared value, custom override, or resolved CSS theme value", defaultRule: "Required String matching a declared option, requested theme key, or custom when allowed", defaultValue: "base", options: [["options", "Array of dictionaries", "Default: []", "Lists choices supplied by the component. Each dictionary needs a value to store and a title to show in the popup."], ["themeValues", "String", "Default: omitted", "Adds choices from one active-theme collection: fontFamilies, fontSizes or spacing."], ["allowsCustom", "Boolean", "Default: false", "Adds a final Custom choice when themeValues is present."]], extra: "<key>themeValues</key><string>fontSizes</string>\n            <key>allowsCustom</key><true/>", usage: "font-size: {{ control.textSize }};\nline-height: {{ control.textSize.lineHeight }};", validation: ["default must match one declared option, requested theme key, or custom when allowed.", "themeValues must be fontFamilies, fontSizes or spacing.", "A select using themeValues cannot declare count."] },
    toggle: { title: "Toggle", summary: "A Boolean switch.", returnType: "Boolean", output: "true or false", defaultRule: "Required Boolean; no implicit value", defaultValue: false, usage: "{{ if control.featured }}featured{{ endif }}", validation: ["default must be a Boolean."] },
    details: { title: "Details", summary: "A compact labelless Boolean details button.", returnType: "Boolean", output: "true or false", defaultRule: "Required Boolean; no implicit value", defaultValue: false, usage: "{{ if control.advanced }}advanced{{ endif }}", note: "Supply toolTip on the property because this control deliberately has no visible label.", validation: ["default must be a Boolean."] },
    button: { title: "Button", summary: "A persistent push button backed by Boolean state and optional mapped outputs.", returnType: "Boolean or the plist type supplied by trueValue/falseValue", output: "Mapped value rendered as String, Number or true/false", defaultRule: "Required Boolean state; no implicit value", defaultValue: false, options: [["systemImage", "String", "Default: omitted", "Optional SF Symbol name."], ["trueValue", "String, Number, Boolean or array", "Default: true", "Template output while state is true."], ["falseValue", "String, Number, Boolean or array", "Default: false", "Template output while state is false."]], extra: "<key>systemImage</key><string>bolt.fill</string>\n            <key>trueValue</key><string>active</string>\n            <key>falseValue</key><string>idle</string>", usage: "data-state=\"{{ control.state }}\"", validation: ["default must be a Boolean."] },
    math: { title: "Math", summary: "A virtual numeric result calculated from constants or other controls.", returnType: "Number (Double)", output: "Locale-independent numeric String", defaultRule: "default may be omitted and is ignored; output is recalculated", virtual: true, options: [["argument1", "Number or String", "Required", "Numeric constant, numeric String, or another control ID."], ["argument2", "Number or String", "Required", "Numeric constant, numeric String, or another control ID."], ["operation", "String", "Required", "+, −, ×, ÷, remainder, min or max using +, -, *, /, %, min, max."], ["round", "Boolean", "Default: true", "Rounds the calculated result."]], extra: "<key>argument1</key><string>width</string>\n            <key>argument2</key><real>2</real>\n            <key>operation</key><string>*</string>\n            <key>round</key><false/>", usage: "width: {{ control.doubleWidth }}px;", validation: ["argument1, argument2 and a supported operation are required.", "Division or remainder by zero returns 0.", "An unresolved argument leaves the derived value unresolved."] },
    textAlignment: { title: "Text alignment", summary: "A segmented control producing logical CSS alignment values.", returnType: "String", output: "start, center, end or justify", defaultRule: "Required String matching one supported value", defaultValue: "start", usage: "text-align: {{ control.alignment }};", validation: ["default must be start, center, end or justify."] },
    fontFamily: { title: "Font family", summary: "A theme font-family choice configured by the project author.", returnType: "String", output: "Resolved CSS font-family String", defaultRule: "Required String: body, heading or monospaced", defaultValue: "body", options: [], usage: "font-family: {{ control.typeface }};", validation: ["default must be body, heading or monospaced."], note: "The inspector also offers additional fonts added in the project Theme Editor. Font families cannot be entered directly in a component inspector." },
    info: { title: "Info", summary: "Presentation-only explanatory text in an inspector group.", returnType: "None", output: "No template value", defaultRule: "default may be omitted; omitted value is an ignored empty String", virtual: true, usage: "No template value", validation: ["No value validation is performed."], note: "Use labels for the explanatory copy. An empty label causes the row to be hidden." },
    divider: { title: "Divider", summary: "A presentation-only visual separator between inspector controls.", returnType: "None", output: "No template value", defaultRule: "default may be omitted; omitted value is an ignored empty String", virtual: true, usage: "No template value", validation: ["No value validation is performed."], note: "Only id, group and type are needed. It has no author-editable state." }
};

const escapeHTML = value => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const type = document.body.dataset.control;
const control = controls[type];
const propertyID = ({ text: "heading", textArea: "body", link: "destination", number: "spacing", padding: "padding", margin: "margin", slider: "intensity", date: "published", color: "textColor", icon: "symbol", select: "textSize", toggle: "featured", details: "advanced", button: "state", math: "doubleWidth", textAlignment: "alignment", fontFamily: "typeface", info: "guidance", divider: "separator" })[type];

const slug = value => value.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replaceAll(/^-|-$/g, "");

const relatedControls = {
    text: [["Text area", "text-area-control.html"], ["Editable text", "editable-text.html"]],
    textArea: [["Text", "text-control.html"], ["Editable text", "editable-text.html"]],
    link: [["Text", "text-control.html"], ["Button", "button-control.html"]],
    number: [["Slider", "slider-control.html"], ["Math", "math-control.html"]],
    padding: [["Margin", "margin-control.html"], ["Theme values", "theme-controls.html"]],
    margin: [["Padding", "padding-control.html"], ["Theme values", "theme-controls.html"]],
    slider: [["Number", "number-control.html"], ["Math", "math-control.html"]],
    color: [["Control arrays", "control-arrays.html"], ["Theme values", "theme-controls.html"]],
    icon: [["Info.plist libraries", "info-plist.html#libraries"], ["Template values", "template-values.html"]],
    fontFamily: [["Select", "select-control.html"], ["Theme values", "theme-controls.html"]],
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
    icon: `<h3>Request the icon library</h3><p>The picker and the published icon both use Foundry’s bundled icon catalogue. Add this once at the top level of the component manifest, beside <code>customItems</code> and <code>templates</code>.</p><pre><code>&lt;key&gt;libraries&lt;/key&gt;
&lt;array&gt;
    &lt;dict&gt;
        &lt;key&gt;id&lt;/key&gt;&lt;string&gt;com.foundry.icons&lt;/string&gt;
        &lt;key&gt;majorVersion&lt;/key&gt;&lt;integer&gt;1&lt;/integer&gt;
    &lt;/dict&gt;
&lt;/array&gt;</code></pre><p>Use the returned name with both Bootstrap Icons classes: <code>bi</code> and <code>bi-{{ control.symbol }}</code>.</p>`,
    button: `<h3>Stored state and returned output</h3><p>The inspector stores Boolean button state. Templates receive <code>trueValue</code> or <code>falseValue</code> when those mappings are supplied; otherwise they receive <code>true</code> or <code>false</code>.</p>`,
    math: `<h3>Referencing another control</h3><p>An argument can be a number or the ID of another numeric property. Foundry resolves dependent math controls repeatedly, allowing one derived value to feed another.</p>`,
    info: `<h3>Supplying the message</h3><p>Use the item’s <code>labels</code> as the explanatory text. If labels is omitted or empty, Foundry hides the info row.</p><pre><code>&lt;key&gt;labels&lt;/key&gt;
&lt;string&gt;Changes here affect every breakpoint.&lt;/string&gt;</code></pre>`
};

const controlKeyNotes = {
    select: {
        id: `<div class="control-note">Replace <code>mySelect</code> with your own identifier. The name is not predefined, but it must be unique in the component and follow the identifier rules above.</div>`,
        default: `<div class="control-note">Use the <code>value</code> of a declared option, a portable key supplied by <code>themeValues</code>, or <code>custom</code> when that choice is available.</div>`,
        count: `<div class="control-note"><strong>Template access uses a zero-based index.</strong> Use <code>{{ control.mySelect[0] }}</code> for the first value and <code>{{ control.mySelect[1] }}</code> for the second. <strong>Not allowed with theme values.</strong> When <code>themeValues</code> is present, the Select must contain one value.</div>`,
        options: `<div class="control-note">May be used by itself or together with <code>themeValues</code>. When combined, developer-declared options appear after the standard and custom theme values.</div>`,
        themeValues: `<div class="control-note"><strong>Popup order:</strong> standard theme values, custom values added in the Theme Editor, developer-declared <code>options</code>, then Custom when enabled.</div><div class="api-table"><div class="api-row api-header"><span>Source</span><span>Template output</span><span>Custom behaviour</span><span>Companion value</span></div><div class="api-row"><strong><code>fontFamilies</code></strong><span>CSS font family</span><span>Custom is a literal choice</span><span>None</span></div><div class="api-row"><strong><code>fontSizes</code></strong><span>CSS size</span><span>Size and Line Height fields</span><span><code>.lineHeight</code></span></div><div class="api-row"><strong><code>spacing</code></strong><span>CSS spacing value</span><span>Custom is a literal choice</span><span>None</span></div></div>`,
        allowsCustom: `<div class="control-note">Requires a named <code>themeValues</code> source. For <code>fontSizes</code>, Custom reveals Size and Line Height fields, initially set to <code>1rem</code> and <code>1.5</code>. For <code>fontFamilies</code> and <code>spacing</code>, it returns the literal value <code>custom</code>, which can enable a separate control.</div>`
    }
};

const controlKeyExamples = {
    select: {
        id: `<key>id</key>
<string>mySelect</string>`,
        labels: [
            ["Single Select", `<key>labels</key>
<string>Font Size</string>`],
            ["Multi Select", `<key>labels</key>
<array>
    <string>Small screen</string>
    <string>Large screen</string>
</array>`]
        ],
        group: `<key>group</key>
<string>Typography</string>`,
        toolTip: `<key>toolTip</key>
<string>Choose the text size.</string>`,
        subtitles: [["Multi Select only", `<key>subtitles</key>
<array>
    <string>Small screen</string>
    <string>Large screen</string>
</array>`]],
        enable: `<key>enable</key>
<dict>
    <key>id</key>
    <string>showTypography</string>
    <key>value</key>
    <true/>
</dict>`,
        default: [
            ["Single Select", `<key>default</key>
<string>base</string>`],
            ["Multi Select", `<key>default</key>
<array>
    <string>compact</string>
    <string>comfortable</string>
</array>`]
        ],
        responsive: `<key>responsive</key>
<false/>`,
        count: [
            ["Multi Select", `<key>count</key>
<integer>2</integer>`],
            ["Template access", `{{ control.mySelect[0] }}
{{ control.mySelect[1] }}`]
        ],
        type: `<key>type</key>
<string>select</string>`,
        options: `<key>options</key>
<array>
    <dict>
        <key>value</key>
        <string>compact</string>
        <key>title</key>
        <string>Compact</string>
    </dict>
    <dict>
        <key>value</key>
        <string>comfortable</string>
        <key>title</key>
        <string>Comfortable</string>
    </dict>
</array>`,
        themeValues: `<key>themeValues</key>
<string>fontSizes</string>`,
        allowsCustom: `<key>allowsCustom</key>
<true/>`
    },
    info: {
        labels: `<key>labels</key>
<string>Changes here affect every breakpoint.</string>`
    }
};

const controlKeyDescriptions = {
    select: {
        id: `The unique name used to store this Select and read it in templates. It must start with a letter and may contain letters, numbers, underscores and hyphens.`,
        labels: `Text shown beside the Select in the Inspector. Use one String for a Single Select. For a <a href="#count">Multi Select</a>, provide one label for each popup.`,
        group: `The Inspector section that contains this Select. Omit the key to place it in Settings.`,
        toolTip: `Help text that explains what the Select changes.`,
        subtitles: `Supporting text for each popup in a <a href="#count">Multi Select</a>. Use this key only when <code>count</code> is present.`,
        enable: `Shows this Select only when another control meets the stated condition.`,
        default: `The initially selected value. Use a declared option value, a standard key supplied by <code>themeValues</code>, or <code>custom</code> when Custom is available. A Multi Select needs one value per popup.`,
        responsive: `Set to true to allow a different selected value at each responsive breakpoint.`,
        type: `Identifies this item as a Select. Always use <code>select</code>.`,
        count: `Creates two to four popups that share the same declared options. Their values are stored as an array and read in templates using a zero-based index. Do not use it with <code>themeValues</code>.`
    },
    details: {
        labels: `Not displayed by this labelless button. Use <code>toolTip</code> to explain its purpose.`
    },
    info: {
        labels: `The explanatory text shown in the Inspector. The Info row is hidden when this value is omitted or empty.`
    }
};

const sharedKeyDescriptions = {
    id: `The unique name used to store this control and read it in templates. It must start with a letter and may contain letters, numbers, underscores and hyphens.`,
    labels: `Text shown beside the control in the Inspector. When <code>count</code> is present, provide one non-empty label for each control.`,
    group: `The Inspector section that contains this control. Omit the key to place it in Settings.`,
    toolTip: `Help text that explains what the control changes.`,
    subtitles: `Supporting text for each member of a control array. Use this key only when <code>count</code> is present.`,
    enable: `Shows this control only when another control meets the stated condition.`,
    default: `The value initially stored for this control. A control array needs one value for each member.`,
    responsive: `Set to true to allow a different value at each responsive breakpoint.`,
    type: `Identifies the kind of Inspector control to create.`,
    count: `Creates two to four controls that are stored as one array. Read each value with a zero-based index such as <code>{{ control.myControl[0] }}</code>.`
};

function minimalKeyExample(key) {
    const supportsCount = !control.virtual && !control.fixedFour;
    const singleLabel = `<key>labels</key>\n<string>${control.title}</string>`;
    const multiLabels = `<key>labels</key>\n<array>\n    <string>First value</string>\n    <string>Second value</string>\n</array>`;
    const singleDefault = `<key>default</key>\n${defaultMarkup(control.defaultValue)}`;
    const multiDefaults = `<key>default</key>\n${defaultMarkup([control.defaultValue, control.defaultValue])}`;
    const examples = {
        id: `<key>id</key>\n<string>${propertyID || "myControl"}</string>`,
        labels: supportsCount ? [["Single control", singleLabel], ["Control array", multiLabels]] : singleLabel,
        group: `<key>group</key>\n<string>Appearance</string>`,
        toolTip: `<key>toolTip</key>\n<string>Choose a value.</string>`,
        subtitles: [["Control array only", `<key>subtitles</key>\n<array>\n    <string>First value</string>\n    <string>Second value</string>\n</array>`]],
        enable: `<key>enable</key>\n<dict>\n    <key>id</key>\n    <string>showControl</string>\n    <key>value</key>\n    <true/>\n</dict>`,
        default: supportsCount ? [["Single control", singleDefault], ["Control array", multiDefaults]] : singleDefault,
        responsive: `<key>responsive</key>\n<false/>`,
        type: `<key>type</key>\n<string>${type}</string>`,
        count: [["Control array", `<key>count</key>\n<integer>2</integer>`]],
        absoluteURL: `<key>absoluteURL</key>\n<true/>`,
        minimum: `<key>minimum</key>\n<real>0</real>`,
        maximum: `<key>maximum</key>\n<real>100</real>`,
        step: `<key>step</key>\n<real>1</real>`,
        units: [["Single control", `<key>units</key>\n<string>px</string>`], ["Control array", `<key>units</key>\n<array>\n    <string>px</string>\n    <string>%</string>\n</array>`]],
        ticks: `<key>ticks</key>\n<integer>11</integer>`,
        showsValueField: `<key>showsValueField</key>\n<true/>`,
        themeValues: `<key>themeValues</key>\n<string>text</string>`,
        colorMath: `<key>colorMath</key>\n<true/>`,
        opacity: `<key>opacity</key>\n<true/>`,
        customColor: `<key>customColor</key>\n<string>#3366CC</string>`,
        customValue: type === "margin" || type === "padding" ? `<key>customValue</key>\n<array>\n    <real>16</real>\n    <real>16</real>\n    <real>16</real>\n    <real>16</real>\n</array>` : null,
        systemImage: `<key>systemImage</key>\n<string>bolt.fill</string>`,
        trueValue: `<key>trueValue</key>\n<string>active</string>`,
        falseValue: `<key>falseValue</key>\n<string>idle</string>`,
        argument1: `<key>argument1</key>\n<string>width</string>`,
        argument2: `<key>argument2</key>\n<real>2</real>`,
        operation: `<key>operation</key>\n<string>*</string>`,
        round: `<key>round</key>\n<false/>`
    };
    return examples[key] || null;
}

function defaultMarkup(value, indent = 0) {
    if (typeof value === "boolean") return `<${value ? "true" : "false"}/>`;
    if (typeof value === "number") return `<real>${value}</real>`;
    if (Array.isArray(value)) {
        const outer = " ".repeat(indent);
        const inner = " ".repeat(indent + 4);
        return `<array>\n${value.map(item => `${inner}${defaultMarkup(item, indent + 4)}`).join("\n")}\n${outer}</array>`;
    }
    return `<string>${value ?? ""}</string>`;
}

function declaration() {
    const label = control.virtual && type !== "info" ? "" : `\n    <key>labels</key><string>${type === "info" ? "Changes here affect every breakpoint." : control.title}</string>`;
    const defaultValue = type === "slider" ? "" : `\n    <key>default</key>${defaultMarkup(control.defaultValue, 4)}`;
    const defaults = control.virtual ? "" : `${defaultValue}\n    <key>responsive</key><false/>`;
    const extraLines = control.extra?.split("\n").map(line => line.trimStart()).join("\n    ");
    const extra = extraLines ? `\n    ${extraLines}` : "";
    return `<dict>\n    <key>id</key><string>${propertyID}</string>${label}\n    <key>group</key><string>${control.virtual ? "Derived values" : "Content"}</string>\n    <key>type</key><string>${type}</string>${extra}${defaults}\n</dict>`;
}

function keyReference(item, nested = false) {
    const [key, kind, requirement, meaning] = item;
    const description = controlKeyDescriptions[type]?.[key] || (key === "type" ? `Identifies this item as ${control.title}. Always use <code>${type}</code>.` : sharedKeyDescriptions[key]) || meaning;
    const requirementTags = requirement.startsWith("Default:")
        ? `<span>Optional</span><span>${requirement}</span>`
        : `<strong>Required</strong>`;
    const keyNote = controlKeyNotes[type]?.[key] || "";
    const example = controlKeyExamples[type]?.[key] || minimalKeyExample(key);
    const examples = Array.isArray(example) ? example : example ? [[null, example]] : [];
    const keyExample = examples.map(([label, code]) => `<div class="key-example-block">${label ? `<p class="example-label">${label}</p>` : ""}<pre class="key-example"><code>${escapeHTML(code)}</code></pre></div>`).join("");
    const customItem = type === "select" && key === "themeValues"
        ? control.options.find(([optionKey]) => optionKey === "allowsCustom")
        : null;
    const nestedReference = customItem ? keyReference(customItem, true) : "";
    const heading = nested ? "h4" : "h3";
    return `<section class="key-reference ${nested ? "key-subsection" : "key-section"}" id="${slug(key)}"><${heading}><code>${key}</code></${heading}><p class="key-kind">${kind}</p><div class="key-meta">${requirementTags}</div><p>${description}</p>${keyExample}${keyNote}${nestedReference}</section>`;
}

function renderPage(page) {
    const defaultKinds = {
        text: "String or String array", textArea: "String or String array", link: "String or String array",
        number: "Number or Number array", padding: "String array", margin: "String array",
        slider: "Number or Number array", date: "String or String array", color: "String or String array",
        icon: "String or String array", select: "String or String array", toggle: "Boolean or Boolean array",
        details: "Boolean or Boolean array", button: "Boolean or Boolean array", textAlignment: "String or String array",
        fontFamily: "String or String array"
    };
    const defaultKey = ["default", defaultKinds[type] || "Value", type === "slider" ? "Default: zero clamped to range" : "Required", "Initial stored value; its plist type must match the control. Slider is the only visible control with an implicit default."];
    const responsiveKey = ["responsive", "Boolean", "Required", "Enables breakpoint-specific overrides."];
    const presentationKeys = commonPresentationKeys.filter(([key]) => {
        if (type === "info") return ["id", "group", "labels", "enable"].includes(key);
        return ["id", "group", "enable"].includes(key);
    });
    const propertyKeys = control.virtual ? presentationKeys : [...commonValueKeys, defaultKey, responsiveKey];
    const optionKeys = [["type", "String", `Required: ${type}`, `Selects the ${type} control.`], ...(control.virtual || control.fixedFour ? [] : commonControlKeys), ...(control.options || []).filter(([key]) => type !== "select" || key !== "allowsCustom")];
    const sections = [
        ["item-keys", "Basic properties"],
        ["control-options", `${control.title} options`],
        ["return-value", "Return value"],
        ["complete-example", "Complete example"],
        ["validation", "Validation and behaviour"],
        ["related", "Related documentation"]
    ];
    const themeAwareTypes = new Set(["select", "color", "padding", "margin", "fontFamily"]);
    const titleBadge = themeAwareTypes.has(type) ? `<span class="capability-badge">Theme-aware</span>` : "";
    const note = control.note ? `<div class="note"><strong>Important:</strong> ${control.note}</div>` : "";
    const guidance = implementationGuidance[type] || "";
    const related = relatedControls[type] || [["All custom controls", "custom-controls.html"], ["Template values", "template-values.html"]];
    if (!related.some(([, href]) => href === "enable-control.html")) related.push(["Conditional visibility", "enable-control.html"]);
    const libraryDeclaration = type === "icon" ? `<key>libraries</key>\n<array>\n    <dict>\n        <key>id</key><string>com.foundry.icons</string>\n        <key>majorVersion</key><integer>1</integer>\n    </dict>\n</array>\n` : "";
    const fullPlist = `${libraryDeclaration}<key>customItems</key>\n<array>\n    ${declaration().replaceAll("\n", "\n    ")}\n</array>`;

    page.innerHTML = `<div class="reference-layout"><article class="reference-article"><div class="breadcrumbs"><a href="index.html">Foundry Developer</a><span>›</span><a href="custom-controls.html">Custom controls</a><span>›</span>${control.title}</div><p class="eyebrow">Control reference</p><h1>${control.title} ${titleBadge}</h1><p class="lede">${control.summary}</p>
    <section id="item-keys"><h2>Basic properties</h2><p>Each item in <code>customItems</code> defines one Inspector item. These keys set its name, placement, initial value and responsive behaviour where applicable.</p>${propertyKeys.map(item => keyReference(item)).join("")}</section>
    <section id="control-options"><h2>${control.title} options</h2><p>These keys sit directly in the same custom-item dictionary. Omitted optional keys use the defaults shown.</p>${optionKeys.map(item => keyReference(item)).join("")}${guidance}${note}</section>
    <section id="return-value"><h2>Return value</h2><p><code>{{ control.${propertyID} }}</code> resolves as <strong>${control.output}</strong>. Stored internally, its value is <strong>${control.returnType}</strong>.</p><pre><code>${escapeHTML(control.usage)}</code></pre></section>
    <section id="complete-example"><h2>Complete example</h2><h3>Info.plist</h3><pre><code>${escapeHTML(fullPlist)}</code></pre><h3>Use it in a template</h3><pre><code>${escapeHTML(control.usage)}</code></pre></section>
    <section id="validation"><h2>Validation and behaviour</h2><ul class="rule-list">${control.validation.map(rule => `<li>${rule}</li>`).join("")}<li>Property IDs must be unique, start with a letter, and contain only letters, numbers, underscores or hyphens.</li></ul></section>
    <section id="related"><h2>Related documentation</h2><div class="page-links">${related.map(([title, href]) => `<a class="card" href="${href}"><strong>${title}</strong><p>Continue with the related API and implementation guidance.</p></a>`).join("")}</div></section><p class="control-footer"><a href="custom-controls.html">← All custom controls</a></p></article><aside class="page-toc" aria-label="On this page"><strong>On this page</strong><ol>${sections.map(([id, title]) => `<li><a href="#${id}">${title}</a></li>`).join("")}</ol></aside></div>`;
}

const page = document.querySelector("main");
if (page && control) renderPage(page);
