# Foundry part API

The current distribution format is a macOS-style `.foundrypack` bundle
(format version 2): a pack-level `Info.plist` at the root, plus typed
`Parts/`, `Templates/`, and `Frameworks/` directories, each item a folder
containing its own `Info.plist` and `Resources/`. While developing, use the
identical structure with a `.foundrydevpack` extension so Finder exposes it
as an ordinary folder and Foundry can watch it in place.

The complete browsable reference lives at the [Foundry Developer API](https://doobox.github.io/foundry-developer-api/). Start
with:

- [Build a part](https://doobox.github.io/foundry-developer-api/quick-start.html)
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
- [Child-part slots](https://doobox.github.io/foundry-developer-api/slots.html)
- [Support and recovery](https://doobox.github.io/foundry-developer-api/manifest-support.html)

## Minimal structure

```text
Example.foundrydevpack/
├── Info.plist
└── Parts/
    └── Example/
        ├── Info.plist
        └── Resources/
            ├── part.html
            ├── part.css
            └── icon.svg
```

The root `Info.plist` identifies the pack itself. A pack may carry any number
of parts under `Parts/`, template bundles under `Templates/`, framework
bundles under `Frameworks/`, and importable asset collections under `Assets/`;
other top-level items are rejected (hidden files such as `.git` are ignored,
so a development pack can live in a checkout).

An asset collection is a folder with an `Info.plist` (requires `id`; may
declare `title`, `license`, `licenseURL`, `attribution` — shown before
import) and a `Resources/` directory of files, nested folders included.
Importing copies files into the project's own asset library.

Root `Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>id</key><string>com.example.pack</string>
    <key>title</key><string>Example Pack</string>
    <key>version</key><string>1.0.0</string>
    <key>minimumAPIVersion</key><integer>1</integer>
</dict>
</plist>
```

`Parts/Example/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>minimumAPIVersion</key><integer>1</integer>
    <key>id</key><string>com.example.part</string>
    <key>title</key><string>Example</string>
    <key>version</key><string>1.0.0</string>
    <key>templates</key>
    <dict>
        <key>html</key><string>part.html</string>
        <key>files</key>
        <array>
            <dict>
                <key>path</key><string>part.css</string>
                <key>scope</key><string>instance</string>
            </dict>
        </array>
    </dict>
</dict>
</plist>
```

### Part identifiers

The top-level `id` must be a lowercase reverse-DNS identifier with at least two dot-separated segments. Each segment may contain lowercase letters, numbers, and internal hyphens. A segment cannot begin or end with a hyphen.

Valid identifiers include:

```text
com.example.hero
com.example.focal-point-hero
uk.co.example.image-slider
```

Uppercase letters, underscores, spaces, empty segments, and leading or trailing hyphens are invalid. For example, `com.example.focal_point`, `com.example.-hero`, and `Com.example.hero` are rejected.

`Parts/Example/Resources/part.html`:

```html
<section {{ part.attributes }}>
    <h2>{{ text="Example heading" }}</h2>
</section>
```

## Images

Use the plain image primitive when the image should be edited directly on the canvas without adding an Inspector control:

```html
<figure {{ part.attributes }}>
    {{ image }}
</figure>
```

Foundry stores this value privately on the part instance. Inside a repeat, every rendered position has its own lazily stored value.

To expose an image in the Inspector, declare a normal image control:

```xml
<key>customItems</key>
<array>
    <dict>
        <key>id</key><string>source</string>
        <key>label</key><string>Image</string>
        <key>group</key><string>Content</string>
        <key>type</key><string>image</string>
        <key>alt</key><string>Default image description</string>
        <key>focalPoint</key><true/>
        <key>renditions</key>
        <array>
            <dict>
                <key>id</key><string>thumbnail</string>
                <key>maximumDimension</key><integer>480</integer>
            </dict>
        </array>
    </dict>
</array>
```

```html
<figure {{ part.attributes }}>
    <img src="{{ control.source }}" width="{{ control.source.width }}" height="{{ control.source.height }}" alt="{{ control.source.alt }}">
</figure>
```

Omitting `defaults` starts with no image. When supplied, use `defaults` containing a `base` string. A non-empty base value must be a path covered by the pack’s top-level `assets` declarations. Image asset defaults are base-only; responsive focal-point editing does not change the asset. Clear restores the declared base default; without one it restores the empty image drop zone. Authors can replace the image from Finder, the Assets panel, or the Inspector image well.

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

Image controls may declare fixed, developer-authored renditions. Each rendition has a unique `id` and a positive `maximumDimension`, which constrains the longest side without upscaling:

```html
<img src="{{ control.source.rendition.thumbnail.href }}" alt="{{ control.source.alt }}">
```

Rendition sizes are part of the pack manifest, not user-editable controls. Requests above Foundry's 3,840 px import limit are clamped to 3,840 px. Foundry stores imported still raster images at no more than 3,840 px on their longest side, preserves SVGs and animated images unchanged, and generates requested smaller renditions only when needed. A source asset and effective size produce one shared file in the published site's global `assets/renditions/` directory, even when many part instances or pages use it. If the source is already small enough, the rendition URL resolves to the source instead and no duplicate file is written.

Unavailable intrinsic values render as an empty string. Foundry reads dimensions when an image is imported (or once when opening an older document) and reads packaged defaults when the pack loads, so these values do not decode images during page rendering.

The exact `src="{{ control.source }}"` binding is also recognized as an image drop target on the canvas. Inside a repeat, use repeat metadata in the control ID when each position has an explicitly declared control, for example `src="{{ control.slide-repeat.position }}"` with controls named `slide-1`, `slide-2`, and so on.

These two forms have different Inspector behaviour inside repeats. Plain `{{ image }}` values are created lazily for the rendered positions and remain hidden from the Inspector. A `{{ control.<id> }}` image is a normal, visible Inspector control, so every repeat position it can address must have a corresponding declared control. Repeated editable text, HTML, and images can be selected and edited on the canvas, but remain part of their parent part: selecting one keeps the parent part's controls in the Inspector, and repeated values cannot be dragged independently.

## Loading and distribution

Open a `.foundrydevpack` directly or put it in
`~/Library/Application Support/Foundry/Packs`. Foundry watches development
packs and reloads a valid edit when the application becomes active. While
authoring, an incomplete item folder (for example a part without its
`Info.plist` yet) is skipped so the rest of the pack keeps loading. Rename the
finished bundle to `.foundrypack`; opening it validates and installs it into
the same Packs directory. Installation rejects a pack that still contains
incomplete items. A pack is a boundary: packs never nest inside other packs,
and one pack distributes any number of parts, templates, and frameworks
through its typed directories.

The retired `.foundryblock`, `.foundryblock-dev`, `block.json`, and
single-part `Contents/` pack layouts are not accepted by the current loader.

## Execution boundary

Packages provide declarative metadata plus website HTML, CSS, JavaScript and
optional PHP. They do not execute native Swift, AppKit, shell or filesystem
code. JavaScript runs only in the rendered website, and PHP runs in exported
pages or Foundry's bundled local-preview runtime.
