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
