# Foundry component API

The current component format is a macOS-style `.foundrypack` bundle with an
`Info.plist` manifest. While developing, use the identical structure with a
`.foundrydevpack` extension so Finder exposes it as an ordinary folder and
Foundry can watch it in place.

The complete browsable reference lives in [`docs`](../docs/index.html). Start
with:

- [Build a component](../docs/quick-start.html)
- [Pack structure and development workflow](../docs/bundle-structure.html)
- [Info.plist overview](../docs/info-plist.html)
- [Identity and metadata](../docs/manifest-identity.html)
- [Template file declarations](../docs/templates.html)
- [Libraries and assets](../docs/manifest-resources.html)
- [Template values and macros](../docs/template-values.html)
- [Custom controls](../docs/custom-controls.html)
- [Conditional control visibility](../docs/enable-control.html)
- [Icon control](../docs/icon-control.html)
- [Editable content primitives](../docs/editable-text.html)
- [Child-component slots](../docs/slots.html)
- [Support and recovery](../docs/manifest-support.html)

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
