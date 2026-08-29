# Foundry Component SDK — API 1

A Foundry component is a self-contained folder ending in
`.foundrycomponent-dev` while it is under development. Choose **Add Development
Component** in Foundry's Components panel to load it. Foundry validates the
folder and watches its files; saved HTML, CSS, SVG, and manifest changes appear
without reinstalling or restarting the app.

Rename or package the finished folder as `.foundrycomponent` for distribution.
Installation, signing, and updates will be added after the API 1 authoring model
stabilises.

## Required files

- `component.json`: identity, version, properties, slots, rendering, assets,
  runtime capabilities, and support metadata.
- An SVG icon referenced by the manifest.
- An HTML template referenced by the manifest.
- Optional CSS, editor-only CSS, runtime JavaScript, and static assets.

Property and slot IDs are stable data identifiers. Never rename one after
shipping without also providing a migration.

## Templates

API 1 is declarative and deterministic: a template cannot execute native code.
Whitespace inside delimiters is optional.

### Required root hooks

The template's root element must include the two component hooks:

```html
<article class="card{{ component.class }}" {{ component.attributes }}>
  …
</article>
```

- `{{ component.class }}` adds scoped production classes when needed. Keep it
  immediately beside your own final class name as shown above.
- `{{ component.attributes }}` adds selection, inline-editing, drag/drop, and
  package-boundary attributes in the canvas. Production export removes editor
  metadata.

These hooks let Foundry supply editor behaviour without package-specific Swift
code or an extra wrapper element.

### Properties

`{{ property.title }}` inserts an HTML-escaped property value. Property values
are safe by default whether used as text or inside a quoted attribute:

```html
<h2>{{ property.title }}</h2>
<a href="{{ property.destination }}">Read more</a>
```

Every referenced property must be declared in `component.json`.

### Named slots

A slot is a location that accepts child components:

```html
<div class="card-media">{% slot id="media" %}</div>
<div class="card-content">{% slot id="content" %}</div>
```

In the canvas an empty slot becomes a named drop zone. In preview and export
the directive emits only its children, with no editor chrome. Slot acceptance
rules and child limits are declared in `component.json`. Children retain their
slot ID in the document, so multiple slots remain distinct.

The early `{{ slot.content }}` prototype still loads with a warning, but new
components should use the slot directive.

### Conditions

Use a Boolean/truthy property or compare a property with a string:

```html
{% if property.showBadge %}
  <span class="badge">{{ property.badge }}</span>
{% endif %}

{% if property.alignment == "center" %}
  <div class="centered">…</div>
{% else %}
  <div>…</div>
{% endif %}
```

Each `if` requires one `endif` and can have at most one `else`.

### Package assets and identifiers

- `{{ asset.images/icon.svg }}` inserts an escaped URL rooted at the package's
  exported asset directory. The path must also appear in `assets` in the
  manifest.
- `{{ instance.id }}` inserts the stable component-instance UUID.
- `{{ package.id }}` inserts the package identifier.

CSS uses `:host` to refer to the current package boundary. Foundry replaces it
with a package-specific selector, preventing ordinary component styles from
leaking into other packages.

## Runtime capabilities

Runtime JavaScript is optional. A package declares each capability it needs.
DOM access and timers are accepted by default in development packages. Network
and local-storage access require approval and are currently rejected.

Packages never receive native macOS, filesystem, shell, or Foundry document
APIs.

## Validation

Foundry checks identifiers, API compatibility, semantic versions, unique
property and slot IDs, control/default compatibility, safe relative paths,
declared files, slot limits, runtime capabilities, template structure, unknown
directives, undeclared properties/assets, and missing or unknown slots. Template
errors include a line number where possible.

Copy `Starter.foundrycomponent-dev` to begin a component.
