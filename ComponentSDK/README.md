# Foundry component API

The current component format is a macOS-style `.foundrypack` bundle with an
`Info.plist` manifest. While developing, use the identical structure with a
`.foundrydevpack` extension so Finder exposes it as an ordinary folder and
Foundry can watch it in place.

The complete browsable reference lives at the [Foundry Developer API](https://doobox.github.io/foundry-developer-api/). Start
with:

- [Build a component](https://doobox.github.io/foundry-developer-api/quick-start.html)
- [Pack structure and development workflow](https://doobox.github.io/foundry-developer-api/bundle-structure.html)
- [Info.plist overview](https://doobox.github.io/foundry-developer-api/info-plist.html)
- [Identity and metadata](https://doobox.github.io/foundry-developer-api/manifest-identity.html)
- [Template file declarations](https://doobox.github.io/foundry-developer-api/templates.html)
- [Libraries and assets](https://doobox.github.io/foundry-developer-api/manifest-resources.html)
- [Template values and macros](https://doobox.github.io/foundry-developer-api/template-values.html)
- [Custom controls](https://doobox.github.io/foundry-developer-api/custom-controls.html)
- [Conditional control visibility](https://doobox.github.io/foundry-developer-api/enable-control.html)
- [Icon control](https://doobox.github.io/foundry-developer-api/icon-control.html)
- [Editable content primitives](https://doobox.github.io/foundry-developer-api/editable-text.html)
- [Child-component slots](https://doobox.github.io/foundry-developer-api/slots.html)
- [Support and recovery](https://doobox.github.io/foundry-developer-api/manifest-support.html)

## Minimal structure

```text
Example.foundrydevpack/
└── Contents/
    ├── Info.plist
    └── Resources/
        ├── component.html
        ├── component.css
        └── icon.svg
```

`Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>minimumAPIVersion</key><integer>1</integer>
    <key>id</key><string>com.example.component</string>
    <key>title</key><string>Example</string>
    <key>version</key><string>1.0.0</string>
    <key>templates</key>
    <dict>
        <key>html</key><string>component.html</string>
        <key>files</key>
        <array>
            <dict>
                <key>path</key><string>component.css</string>
                <key>scope</key><string>instance</string>
            </dict>
        </array>
    </dict>
</dict>
</plist>
```

`Contents/Resources/component.html`:

```html
<section {{ component.attributes }}>
    <h2>{{ text="Example heading" }}</h2>
</section>
```

## Images

Use the plain image primitive when the image should be edited directly on the canvas without adding an Inspector control:

```html
<figure {{ component.attributes }}>
    {{ image }}
</figure>
```

Foundry stores this value privately on the component instance. Inside a repeat, every rendered position has its own lazily stored value.

To expose an image in the Inspector, declare a normal image control:

```xml
<key>customItems</key>
<array>
    <dict>
        <key>id</key><string>source</string>
        <key>labels</key><string>Image</string>
        <key>group</key><string>Content</string>
        <key>type</key><string>image</string>
        <key>alt</key><string>Default image description</string>
        <key>focalPoint</key><true/>
    </dict>
</array>
```

```html
<figure {{ component.attributes }}>
    <img src="{{ control.source }}" width="{{ control.source.width }}" height="{{ control.source.height }}" alt="{{ control.source.alt }}">
</figure>
```

Omitting `default` starts with no image. A non-empty default must be a path covered by the pack’s top-level `assets` declarations. Clear restores the declared default; without one it restores the empty image drop zone. Authors can replace the image from Finder, the Assets panel, or the Inspector image well.

The optional `alt` key defaults to an empty string. Foundry automatically places an editable field labelled **Alt** on the row immediately below the image well. The image control also exposes structured companion values:

- `{{ control.source }}` and `{{ control.source.href }}` — resolved image URL.
- `{{ control.source.width }}` and `{{ control.source.height }}` — intrinsic, orientation-corrected pixel dimensions.
- `{{ control.source.mimeType }}` — MIME type, such as `image/png`.
- `{{ control.source.byteCount }}` — exact stored size in bytes.
- `{{ control.source.filename }}` — original filename.
- `{{ control.source.extension }}` — lowercase filename extension without the dot.
- `{{ control.source.aspectRatio }}` — intrinsic width divided by height.
- `{{ control.source.alt }}` — escaped editable alternative text.
- `{{ control.source.focalPointX }}` and `{{ control.source.focalPointY }}` — instance-specific focal-point percentages from `0` to `100`, defaulting to `50`.
- `{{ control.source.position }}` — the focal point as a ready-to-use CSS pair such as `35% 60%`.

Focal-point editing is opt-in. Add `<key>focalPoint</key><true/>` to let the user set it directly on the Inspector image preview; omitting the key or setting it to false leaves the image well unchanged and returns the centred defaults. Use the same `position` value with either replaced images or backgrounds:

```css
object-position: {{ control.source.position }};
background-position: {{ control.source.position }};
```

Unavailable intrinsic values render as an empty string. Foundry reads dimensions when an image is imported (or once when opening an older document) and reads packaged defaults when the pack loads, so these values do not decode images during page rendering.

The exact `src="{{ control.source }}"` binding is also recognized as an image drop target on the canvas. Inside a repeat, use repeat metadata in the control ID when each position has an explicitly declared control, for example `src="{{ control.slide-repeat.position }}"` with controls named `slide-1`, `slide-2`, and so on.

These two forms have different Inspector behaviour inside repeats. Plain `{{ image }}` values are created lazily for the rendered positions and remain hidden from the Inspector. A `{{ control.<id> }}` image is a normal, visible Inspector control, so every repeat position it can address must have a corresponding declared control. Repeated editable text, HTML, and images can be selected and edited on the canvas, but remain part of their parent component: selecting one keeps the parent component's controls in the Inspector, and repeated values cannot be dragged independently.

## Loading and distribution

Open a `.foundrydevpack` directly or put it in
`~/Library/Application Support/Foundry/Packs`. Foundry watches development
packs and reloads a valid edit when the application becomes active. Rename the
finished bundle to `.foundrypack`; opening it validates and installs it into the
same Packs directory. Packs may recursively contain other packs. A pack is a
component by default; an outer packaging container sets the optional Boolean
`collection` key to `true` so Foundry skips the parent itself while continuing
to discover its nested components. A collection manifest contains only
`collection = true`; component metadata belongs to its nested packs.

The retired `.foundrycomponent`, `.foundrycomponent-dev` and `component.json`
prototype formats are not accepted by the current loader.

## Execution boundary

Packages provide declarative metadata plus website HTML, CSS, JavaScript and
optional PHP. They do not execute native Swift, AppKit, shell or filesystem
code. JavaScript runs only in the rendered website, and PHP runs in exported
pages or Foundry's bundled local-preview runtime.
