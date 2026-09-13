# Block stress testing

`block-stress-test.sh` creates a physical collection of block packages in Foundry's normal installed-packs directory. Foundry requires no test-specific loading code and processes these packages through its production discovery, validation, and catalog pipeline.

Create 1,000 blocks with files similar in size to ordinary built-ins:

```sh
DeveloperTools/block-stress-test.sh install 1000 realistic
```

Create 1,000 blocks with 128 KiB HTML, CSS, and JavaScript files and an SVG icon close to the 64 KiB limit:

```sh
DeveloperTools/block-stress-test.sh install 1000 heavy
```

Quit Foundry before generating or removing the collection. Launch Foundry normally after generation to measure a cold catalog load.

Remove the generated collection after testing:

```sh
DeveloperTools/block-stress-test.sh remove
```

The script refuses to overwrite an existing stress collection and only removes the exact `FoundryStressTest.foundrypack` path. Set `FOUNDRY_STRESS_PACKS_ROOT` to exercise the generator in another directory without touching Application Support.
