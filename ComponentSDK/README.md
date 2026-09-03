# Foundry component API

The current component format is a macOS-style `.foundrypack` bundle with an
`Info.plist` manifest. While developing, use the identical structure with a
`.foundrydevpack` extension so Finder exposes it as an ordinary folder and
Foundry can watch it in place.

The complete browsable reference lives in [`docs`](../docs/index.html). Start
with:

- [Build a component](../docs/quick-start.html)
- [Pack structure and development workflow](../docs/bundle-structure.html)
- [Info.plist reference](../docs/info-plist.html)
- [Template values and scopes](../docs/template-values.html)
- [Custom controls](../docs/custom-controls.html)
- [Editable content primitives](../docs/editable-text.html)
- [Child-component slots](../docs/slots.html)

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
    <key>type</key><string>component</string>
    <key>CFBundleIdentifier</key><string>com.example.component</string>
    <key>title</key><string>Example</string>
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
<section id="{{ id }}" {{ component.attributes }}>
    <h2>{{ text="Example heading" }}</h2>
</section>
```

## Loading and distribution

Open a `.foundrydevpack` directly or put it in
`~/Library/Application Support/Foundry/Packs`. Foundry watches development
packs and reloads a valid edit when the application becomes active. Rename the
finished bundle to `.foundrypack`; opening it validates and installs it into the
same Packs directory. Packs may recursively contain component or collection
packs.

The retired `.foundrycomponent`, `.foundrycomponent-dev` and `component.json`
prototype formats are not accepted by the current loader.

## Execution boundary

Packages provide declarative metadata plus website HTML, CSS, JavaScript and
optional PHP. They do not execute native Swift, AppKit, shell or filesystem
code. JavaScript runs only in the rendered website, and PHP runs in exported
pages or Foundry's bundled local-preview runtime.
