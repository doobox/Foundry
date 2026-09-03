# Development fixtures

`BrokenComponent.foundrydevpack` is intentionally invalid. Open it with a development build of Foundry to exercise the Developer panel. It must fail validation because its identifier is not lowercase reverse-DNS and its declared HTML template does not exist.

The fixture lives outside the app's synchronized `Foundry` source group, so it is not copied into shipping builds.
