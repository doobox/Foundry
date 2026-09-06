import Foundation
import CryptoKit
import Testing
@testable import Foundry

struct ComponentPackageTests {
    @Test
    func removedFontFamilyControlIsRejected() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>type</key><string>fontFamily</string>
        </dict></plist>
        """

        do {
            _ = try PropertyListDecoder().decode(
                ComponentPackageControl.self,
                from: Data(plist.utf8)
            )
            Issue.record("The removed fontFamily control unexpectedly decoded.")
        } catch {
            // Unknown control types must fail package decoding.
        }
    }

    @Test @MainActor
    func developmentFixturesValidateExpectedContracts() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryURL.appending(
            path: "DevelopmentFixtures/BrokenComponent.foundrydevpack",
            directoryHint: .isDirectory
        )

        let header = try FoundryPackLoader.load(from: fixtureURL)
        #expect(!header.isCollection)

        do {
            _ = try ComponentPackageLoader.load(from: fixtureURL)
            Issue.record("The intentionally broken component unexpectedly loaded.")
        } catch ComponentPackageLoadingError.invalid(let diagnostics) {
            #expect(diagnostics.contains { $0.message.contains("reverse-DNS") })
            #expect(diagnostics.contains { $0.message.contains("does not exist") })
        } catch {
            Issue.record("Expected component validation diagnostics, but received: \(error)")
        }

        let enablePackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/EnableConditions.foundrydevpack")
        )
        #expect(enablePackage.manifest.identifier == "dev.foundry.enable_conditions")
        #expect(enablePackage.manifest.properties.contains { $0.enable?.id == "titles[2]" })

        let themePackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ThemeValues.foundrydevpack")
        )
        #expect(themePackage.manifest.identifier == "dev.foundry.theme_values")
        #expect(themePackage.manifest.properties.contains { $0.control.themeValueSource == .fontFamilies })
        #expect(themePackage.manifest.properties.contains { $0.id == "topBorder" && $0.control.themeValueDefault == "accent" })
        #expect(themePackage.manifest.properties.contains { $0.id == "bottomBorder" && $0.control.themeValueDefault == "links" })

        let scopedAssetsPackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ScopedAssets.foundrydevpack")
        )
        #expect(scopedAssetsPackage.manifest.identifier == "dev.foundry.scoped_assets")
        #expect(scopedAssetsPackage.manifest.assets.count == 3)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .page }.count == 2)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .site }.count == 1)

        let expressionPackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ExpressionEngine.foundrydevpack")
        )
        #expect(expressionPackage.manifest.identifier == "dev.foundry.expression_engine")
        let expressionHTML = ComponentTemplateRenderer.render(
            expressionPackage.htmlTemplate,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: expressionPackage.manifest.identifier,
                properties: [
                    "status": .string("featured"),
                    "enabled": .boolean(true),
                    "score": .number(72),
                    "threshold": .number(60),
                    "base": .number(10),
                    "offset": .number(6),
                    "multiplier": .number(3),
                    "labels": .array([.string("Alpha"), .string("Beta")])
                ],
                slots: [:],
                environment: .canvas
            )
        )
        #expect(expressionHTML.contains("<strong>28</strong>"))
        #expect(expressionHTML.contains("Featured and above threshold"))
        #expect(expressionHTML.contains("Alpha · Beta"))
        #expect(expressionHTML.contains("editor-only"))
    }

    @Test
    func linkControlResolvesPagesResourcesAnchorsTargetsAndAttributes() {
        let page = Page(title: "Profile", slug: "profile")
        let asset = ProjectAsset(filename: "guide.pdf", mediaType: "application/pdf", byteCount: 10)
        let link = ComponentLink(
            destination: .page(page.id),
            anchor: "bio",
            opensInNewWindow: true,
            attributes: [.init(name: "title", value: "Read & learn")]
        )
        let resolved = ComponentLinkResolver.resolve(
            link, pages: [page], folders: [], assets: [asset],
            publicURL: "https://example.com/", absoluteURL: true
        )
        #expect(resolved.href == "https://example.com/profile/#bio")
        #expect(resolved.target == "_blank")
        #expect(resolved.attributes == "title=\"Read &amp; learn\" rel=\"noopener noreferrer\"")

        let parentPage = Page(title: "Services", slug: "services")
        let childPage = Page(
            title: "Design",
            slug: "design",
            parentPageID: parentPage.id
        )
        let nestedPageLink = ComponentLinkResolver.resolve(
            .init(destination: .page(childPage.id)),
            pages: [parentPage, childPage],
            folders: [],
            assets: [],
            publicURL: "",
            absoluteURL: false
        )
        #expect(nestedPageLink.href == "/services/design/")

        let resource = ComponentLinkResolver.resolve(
            .init(destination: .resource(asset.id)), pages: [page], folders: [], assets: [asset],
            publicURL: "", absoluteURL: true
        )
        #expect(resource.href == "/\(asset.exportPath)")

        let resourceFolder = ProjectAssetFolder(name: "Test Folder", children: [.asset(asset)])
        let nestedResource = ComponentLinkResolver.resolve(
            .init(destination: .resource(asset.id)), pages: [page], folders: [], assets: [asset],
            assetLibrary: [.folder(resourceFolder)], publicURL: "", absoluteURL: true
        )
        #expect(nestedResource.href == "/assets/test-folder/guide.pdf")

        let folder = PageFolder(name: "Downloads", slug: "downloads")
        var placedAsset = asset
        placedAsset.exportDirectory = .folder(folder.id)
        let placedResource = ComponentLinkResolver.resolve(
            .init(destination: .resource(asset.id)), pages: [page], folders: [folder], assets: [placedAsset],
            publicURL: "", absoluteURL: true
        )
        #expect(placedResource.href == "/downloads/guide.pdf")
    }

    @Test
    func controlArraysDecodePersistAndRenderIndexedValues() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.arrays</string>
        <key>title</key><string>Arrays</string><key>description</key><string>Array controls</string>
        <key>author</key><string>Foundry</string><key>version</key><string>1.0.0</string><key>group</key><string>Other</string>
        <key>tags</key><array/><key>assets</key><array/><key>slots</key><array/>
        <key>customItems</key><array><dict>
        <key>id</key><string>palette</string><key>labels</key><array><string>One</string><string>Two</string><string>Three</string><string>Four</string></array><key>group</key><string>Appearance</string>
        <key>subtitles</key><array><string>First</string><string>Second</string><string>Third</string><string>Fourth</string></array>
        <key>toolTip</key><string>Four colours</string>
        <key>type</key><string>color</string><key>count</key><integer>4</integer>
        <key>default</key><array><string>#111111</string><string>#222222</string><string>#333333</string><string>#444444</string></array>
        <key>responsive</key><true/>        </dict></array>
        <key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(plist.utf8))
        let property = try #require(manifest.properties.first)
        #expect(property.control.count == 4)
        #expect(property.labels == ["One", "Two", "Three", "Four"])
        #expect(property.subtitles == ["First", "Second", "Third", "Fourth"])
        #expect(property.toolTip == "Four colours")

        let value = ComponentPackageValue.array([.string("red"), .string("green"), .string("blue")])
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ComponentPackageValue.self, from: data) == value)

        let context = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.arrays",
            properties: ["palette": value], slots: [:]
        )
        #expect(ComponentTemplateRenderer.render("{{ control.palette[1] }}", context: context) == "green")
        #expect(ComponentTemplateRenderer.render("{{ property.palette[1] }}", context: context).isEmpty)
    }

    @Test
    func namedThemeValuesDecodePopulateAndResolve() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.theme-values</string>
        <key>title</key><string>Theme Values</string><key>description</key><string>Named theme sources</string>
        <key>author</key><string>Foundry</string><key>version</key><string>1.0.0</string><key>group</key><string>Other</string>
        <key>tags</key><array/><key>assets</key><array/><key>slots</key><array/>
        <key>customItems</key><array><dict>
        <key>id</key><string>tone</string><key>labels</key><string>Tone</string><key>group</key><string>Appearance</string>
        <key>type</key><string>select</string><key>themeValues</key><string>spacing</string>
        <key>allowsCustom</key><true/>
        <key>options</key><array><dict><key>value</key><string>inherit</string><key>title</key><string>Inherit</string></dict></array>
        <key>default</key><string>md</string><key>responsive</key><false/>
        </dict></array>
        <key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(plist.utf8))
        let property = try #require(manifest.properties.first)

        #expect(property.control.themeValues == .source(.spacing))
        #expect(property.control.themeValueSource == .spacing)
        #expect(property.control.allowsCustom == true)
        let diagnostics = ComponentPackageValidator.validate(manifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(!diagnostics.contains { $0.location.contains("themeValues") || $0.message.contains("select default") })
        #expect(ComponentPackageThemeValueResolver.choices(for: .spacing, theme: .standard).contains { $0.value == "md" })
        #expect(ComponentPackageThemeValueResolver.resolve("md", from: .spacing, theme: .standard) == "var(--foundry-space-md)")
        for source in ComponentPackageThemeValueSource.allCases {
            #expect(ComponentPackageThemeValueResolver.choices(for: source, theme: .standard).allSatisfy {
                !$0.label.contains("—")
            })
        }

        var theme = Theme.standard
        theme.typography.customFontSizes.append(.init(id: "display", title: "Display", size: 5, lineHeight: 1.5))
        let sizeChoices = ComponentPackageThemeValueResolver.choices(for: .fontSizes, theme: theme)
        #expect(sizeChoices.first?.value == "xs")
        #expect(sizeChoices.last?.value == "display")
        #expect(sizeChoices.last?.separatorBefore == true)

        let countedThemeSelect = plist
            .replacingOccurrences(
                of: "<key>themeValues</key><string>spacing</string>",
                with: "<key>themeValues</key><string>fontSizes</string>"
            )
            .replacingOccurrences(
                of: "<key>default</key><string>md</string><key>responsive</key><false/>",
                with: "<key>default</key><string>base</string><key>responsive</key><false/><key>count</key><integer>2</integer>"
            )
        let schemaDiagnostics = try ComponentPackageManifestSchema.diagnostics(
            for: Data(countedThemeSelect.utf8)
        )
        #expect(schemaDiagnostics.contains {
            $0.location.hasSuffix(".count")
                && $0.message == "A select control using themeValues cannot be a multi control; remove count."
        })

        let countedThemeColor = countedThemeSelect
            .replacingOccurrences(
                of: "<key>type</key><string>select</string>",
                with: "<key>type</key><string>color</string>"
            )
        let colorSchemaDiagnostics = try ComponentPackageManifestSchema.diagnostics(
            for: Data(countedThemeColor.utf8)
        )
        #expect(colorSchemaDiagnostics.contains {
            $0.location.hasSuffix(".count")
                && $0.message == "A color control using themeValues cannot be a multi control; remove count."
        })

        let booleanThemeValues = Data(
            plist.replacingOccurrences(
                of: "<key>themeValues</key><string>spacing</string>",
                with: "<key>themeValues</key><true/>"
            ).utf8
        )
        #expect(try ComponentPackageManifestSchema.diagnostics(for: booleanThemeValues).contains {
            $0.location.hasSuffix(".themeValues") && $0.message == "themeValues must be a string."
        })

        do {
            _ = try PropertyListDecoder().decode(
                ComponentPackageControl.self,
                from: Data("<plist version=\"1.0\"><dict><key>type</key><string>color</string><key>themeValues</key><true/></dict></plist>".utf8)
            )
            Issue.record("Boolean themeValues should be rejected")
        } catch {
            // String-only decoding intentionally rejects the removed API.
        }
    }

    @Test
    func fontFamilyThemeSelectRejectsCustomValues() throws {
        let item = """
        <dict>
            <key>id</key><string>typeface</string>
            <key>labels</key><string>Typeface</string>
            <key>group</key><string>Typography</string>
            <key>type</key><string>select</string>
            <key>themeValues</key><string>fontFamilies</string>
            <key>allowsCustom</key><true/>
            <key>default</key><string>body</string>
            <key>responsive</key><true/>
        </dict>
        """
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifest(withCustomItems: item).utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        #expect(diagnostics.contains {
            $0.location.hasSuffix("allowsCustom")
                && $0.message.contains("add fonts in the Theme Editor")
        })
    }

    @Test
    func malformedControlFieldsProduceActionableSchemaDiagnostics() throws {
        let validItem = """
        <dict>
            <key>id</key><string>example</string>
            <key>labels</key><string>Example</string>
            <key>type</key><string>text</string>
            <key>default</key><string>Hello</string>
            <key>responsive</key><false/>
        </dict>
        """
        let cases: [(replacement: String, locationSuffix: String, message: String)] = [
            (
                validItem.replacingOccurrences(of: "<key>type</key><string>text</string>", with: "<key>type</key><integer>1</integer>"),
                ":type", "type must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "<string>text</string>", with: "<string>fontFamily</string>"),
                ":type", "Unknown control type 'fontFamily'."
            ),
            (
                validItem.replacingOccurrences(of: "<key>labels</key><string>Example</string>", with: "<key>labels</key><array><string>Example</string></array>"),
                ":labels", "labels must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "<key>responsive</key><false/>", with: "<key>responsive</key><string>false</string>"),
                ":responsive", "responsive must be a Boolean."
            ),
            (
                validItem.replacingOccurrences(of: "<key>default</key><string>Hello</string>", with: "<key>default</key><dict/>"),
                ":default", "default must be a string, number, Boolean, or array of those values."
            ),
            (
                validItem.replacingOccurrences(of: "<key>responsive</key><false/>", with: "<key>responsive</key><false/><key>minimum</key><string>zero</string>"),
                ":minimum", "minimum must be a number."
            ),
            (
                validItem.replacingOccurrences(of: "<key>responsive</key><false/>", with: "<key>responsive</key><false/><key>count</key><string>two</string>"),
                ":count", "count must be an integer."
            )
        ]

        for testCase in cases {
            let diagnostics = try ComponentPackageManifestSchema.diagnostics(
                for: Data(manifest(withCustomItems: testCase.replacement).utf8)
            )
            #expect(diagnostics.contains {
                $0.location.hasSuffix(testCase.locationSuffix) && $0.message == testCase.message
            })
        }

        let malformedOptions = validItem.replacingOccurrences(
            of: "<key>responsive</key><false/>",
            with: "<key>responsive</key><false/><key>options</key><array><string>bad</string></array>"
        )
        #expect(try ComponentPackageManifestSchema.diagnostics(
            for: Data(manifest(withCustomItems: malformedOptions).utf8)
        ).contains {
            $0.location.hasSuffix(":options[0]") && $0.message == "Each options entry must be a dictionary."
        })
    }

    @Test
    func enableConditionsDecodeAndEvaluateScalarAndIndexedValues() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.enable</string>
        <key>title</key><string>Enable</string><key>description</key><string>Conditional controls</string>
        <key>version</key><string>1.0.0</string><key>group</key><string>Other</string>
        <key>assets</key><array/><key>slots</key><array/>
        <key>customItems</key><array>
        <dict><key>id</key><string>mode</string><key>labels</key><string>Mode</string><key>type</key><string>select</string><key>options</key><array><dict><key>value</key><string>featured</string><key>title</key><string>Featured</string></dict></array><key>default</key><string>featured</string><key>responsive</key><false/></dict>
        <dict><key>id</key><string>titles</string><key>labels</key><array><string>One</string><string>Two</string><string>Three</string></array><key>type</key><string>text</string><key>count</key><integer>3</integer><key>default</key><array><string>One</string><string>Two</string><string>Featured story</string></array><key>responsive</key><false/></dict>
        <dict><key>id</key><string>detail</string><key>labels</key><string>Detail</string><key>type</key><string>text</string><key>default</key><string>Visible</string><key>responsive</key><false/><key>enable</key><dict><key>id</key><string>titles[2]</string><key>operation</key><string>containsInsensitive</string><key>value</key><string>featured</string></dict></dict>
        </array><key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(plist.utf8))
        let enabledProperty = try #require(manifest.properties.last)
        #expect(enabledProperty.enable?.id == "titles[2]")
        #expect(enabledProperty.enable?.operation == "containsInsensitive")

        #expect(ComponentPackageEnableEvaluator.evaluate(
            .string("Featured story"),
            operation: enabledProperty.enable?.operation ?? "",
            expected: enabledProperty.enable?.value
        ))
        #expect(!ComponentPackageEnableEvaluator.evaluate(
            .string("Ordinary story"),
            operation: enabledProperty.enable?.operation ?? "",
            expected: enabledProperty.enable?.value
        ))
        #expect(ComponentPackageEnableEvaluator.evaluate(.string(""), operation: "isEmpty", expected: nil))
        #expect(ComponentPackageEnableEvaluator.evaluate(.number(10), operation: ">=", expected: .number(10)))
    }

    @Test
    func virtualControlsAndButtonOutputsResolveFromManifestValues() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.derived</string>
        <key>title</key><string>Derived</string><key>description</key><string>Derived controls</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/><key>slots</key><array/>
        <key>customItems</key><array>
        <dict><key>id</key><string>amount</string><key>labels</key><string>Amount</string><key>group</key><string>Test</string><key>type</key><string>number</string><key>default</key><real>21</real><key>responsive</key><false/></dict>
        <dict><key>id</key><string>action</string><key>labels</key><string>Action</string><key>group</key><string>Test</string><key>type</key><string>button</string><key>trueValue</key><string>active</string><key>falseValue</key><string>ready</string><key>default</key><false/><key>responsive</key><false/></dict>
        <dict><key>id</key><string>doubled</string><key>group</key><string>Test</string><key>type</key><string>math</string><key>argument1</key><string>amount</string><key>argument2</key><real>2</real><key>operation</key><string>*</string><key>round</key><false/></dict>
        </array><key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(plist.utf8))
        let resolved = ComponentPackageDerivedValueResolver.resolve(
            ["amount": .number(21), "action": .boolean(true)],
            properties: manifest.properties
        )
        #expect(resolved["doubled"] == .number(42))
        #expect(resolved["action"] == .string("active"))
    }

    @Test
    func phpCapabilityForcesPageExtensionWithoutAnInlinePHPTemplate() throws {
        let defaultManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(!defaultManifest.requiresPhp)

        let identifier = "com.example.php\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>",
                with: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict><dict><key>path</key><string>server/endpoint.php</string></dict></array>"
            )
            .replacingOccurrences(
                of: "<key>templates</key>",
                with: "<key>requiresPhp</key><true/>\n            <key>templates</key>"
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["server/endpoint.php": "<?php echo 'ready'; ?>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)

        let component = ComponentNode(type: ComponentType(rawValue: identifier))
        let site = Site(name: "PHP", pages: [Page(title: "Home", slug: "index", components: [component])])
        let bundle = StaticSiteRenderer().render(site: site)

        #expect(package.manifest.requiresPhp)
        #expect(bundle.file(at: "index.html") == nil)
        #expect(bundle.file(at: "index.php") != nil)
        #expect(bundle.file(at: "files/endpoint.php") != nil)
    }

    @Test
    func scopedAssetsPublishOnceAtTheirPageAndSiteDestinations() throws {
        let identifier = "com.example.scoped\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>",
                with: """
                <key>assets</key><array>
                    <dict><key>path</key><string>images/icon.svg</string></dict>
                    <dict><key>path</key><string>shared/icons</string><key>scope</key><string>site</string></dict>
                </array>
                """
            )
        let template = """
        <div {{ component.attributes }}>{{ asset.images/icon.svg }}|{{ asset.shared/icons/star.svg }}|{{ path.siteAssets }}|{{ site.baseURL }}|{{ page.url }}|{{ if preview }}preview{{ elseif published }}published{{ endif }}{{ slot id="content" }}</div>
        """
        let packageURL = try makePackage(
            manifest: manifest,
            template: template,
            additionalFiles: ["shared/icons/star.svg": "<svg>star</svg>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)

        let homeComponent = ComponentNode(type: ComponentType(rawValue: identifier))
        let aboutComponent = ComponentNode(type: ComponentType(rawValue: identifier))
        var site = Site(name: "Scoped", pages: [
            Page(title: "Home", slug: "index", components: [homeComponent]),
            Page(title: "About", slug: "about", components: [aboutComponent])
        ])
        site.publicURL = "https://example.com"
        let bundle = StaticSiteRenderer().render(site: site)
        let previewBundle = StaticSiteRenderer(environment: .preview).render(site: site)

        #expect(bundle.errors.isEmpty)
        #expect(bundle.file(at: "files/icon.svg") != nil)
        #expect(bundle.file(at: "about/files/icon.svg") != nil)
        #expect(bundle.files.filter { $0.path == "assets/shared/icons/star.svg" }.count == 1)
        #expect(bundle.file(at: "index.html")?.contents.contains("files/icon.svg|assets/shared/icons/star.svg|assets|https://example.com|https://example.com/|published") == true)
        #expect(bundle.file(at: "about/index.html")?.contents.contains("files/icon.svg|../assets/shared/icons/star.svg|../assets|https://example.com|https://example.com/about/|published") == true)
        #expect(previewBundle.file(at: "index.html")?.contents.contains("|preview") == true)
    }

    @Test @MainActor
    func canvasResolvesAndServesDeclaredPackageAssetsAtEitherScope() throws {
        let identifier = "com.example.canvasassets\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>",
                with: """
                <key>assets</key><array>
                    <dict><key>path</key><string>images/icon.svg</string></dict>
                    <dict><key>path</key><string>shared/icons</string><key>scope</key><string>site</string></dict>
                </array>
                """
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<div {{ component.attributes }}><img src=\"{{ asset.images/icon.svg }}\"><img src=\"{{ asset.shared/icons/star.svg }}\">{{ slot id=\"content\" }}</div>",
            additionalFiles: ["shared/icons/star.svg": "<svg>star</svg>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        let component = ComponentNode(type: ComponentType(rawValue: identifier))
        let page = Page(title: "Canvas assets", slug: "index", components: [component])

        let html = HTMLPageRenderer().render(page: page, theme: .standard)
        let pageAssetReference = "\(CanvasAssetSchemeHandler.packageScheme)://\(identifier)/images/icon.svg"
        let siteAssetReference = "\(CanvasAssetSchemeHandler.packageScheme)://\(identifier)/shared/icons/star.svg"
        #expect(html.contains(pageAssetReference))
        #expect(html.contains(siteAssetReference))

        let handler = CanvasAssetSchemeHandler(assets: [:], packages: [identifier: package])
        let pageAssetURL = try #require(URL(string: pageAssetReference))
        let siteAssetURL = try #require(URL(string: siteAssetReference))
        #expect(handler.resource(for: pageAssetURL)?.mediaType == "image/svg+xml")
        #expect(handler.resource(for: siteAssetURL)?.data == Data("<svg>star</svg>".utf8))

        let undeclaredURL = try #require(URL(string: "\(CanvasAssetSchemeHandler.packageScheme)://\(identifier)/private.txt"))
        #expect(handler.resource(for: undeclaredURL) == nil)
    }

    @Test
    func repeatRendersArbitraryMarkupAndPositionMetadata() {
        let template = """
        {{ repeat 3 }}
        <span data-index="{{ repeat.index }}">{{ repeat.position }}/{{ repeat.count }} {{ if repeat.first }}first{{ elseif repeat.last }}last{{ endif }}</span>
        {{ endrepeat }}
        """
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.repeat",
            properties: [:],
            slots: [:]
        )

        let rendered = ComponentTemplateRenderer.render(template, context: context)

        #expect(rendered.contains("data-index=\"0\">1/3 first"))
        #expect(rendered.contains("data-index=\"1\">2/3 "))
        #expect(rendered.contains("data-index=\"2\">3/3 last"))
        #expect(rendered.components(separatedBy: "<span").count - 1 == 3)
    }

    @Test
    func nestedRepeatExposesParentMetadata() {
        let template = "{{ repeat 2 }}{{ repeat 2 }}{{ repeat.parent.position }}.{{ repeat.position }};{{ endrepeat }}{{ endrepeat }}"
        let rendered = ComponentTemplateRenderer.render(
            template,
            context: .init(instanceID: UUID(), packageIdentifier: "com.example.repeat", properties: [:], slots: [:])
        )

        #expect(rendered == "1.1;1.2;2.1;2.2;")
    }

    @Test
    func controlRepeatKeepsPrimitiveKeysStableAcrossCountChanges() {
        let template = """
        {{ repeat control.itemCount }}<article>{{ text="Card" }}{{ image card-repeat.position }}</article>{{ endrepeat }}
        <footer>{{ text="Footer" }}</footer>
        """
        let maximums = ["itemCount": 4]
        let textPrimitives = ComponentTemplateRenderer.textPrimitives(in: template, repeatMaximums: maximums)
        #expect(textPrimitives.map(\.key) == ["content1", "content2", "content3", "content4", "content5"])

        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.repeat",
            properties: [
                "itemCount": .number(2),
                "content1": .string("One"),
                "content2": .string("Two"),
                "content5": .string("Footer value"),
                "card-1": .string("one.jpg"),
                "card-2": .string("two.jpg")
            ],
            slots: [:],
            repeatMaximums: maximums
        )
        let rendered = ComponentTemplateRenderer.render(template, context: context)

        #expect(rendered.components(separatedBy: "<article>").count - 1 == 2)
        #expect(rendered.contains("One<img class=\"foundry-image\" src=\"one.jpg\""))
        #expect(rendered.contains("Two<img class=\"foundry-image\" src=\"two.jpg\""))
        #expect(rendered.contains("<footer>Footer value</footer>"))
        #expect(!rendered.contains("content3"))

        let editorContext = ComponentTemplateContext(
            instanceID: context.instanceID,
            packageIdentifier: context.packageIdentifier,
            properties: context.properties,
            slots: [:],
            enablesEditorMarkup: true,
            repeatMaximums: maximums
        )
        let editorHTML = ComponentTemplateRenderer.render(template, context: editorContext)
        #expect(editorHTML.contains("data-foundry-primitive-property=\"content1\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"card-1\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"content5\"") == false)
    }

    @Test
    func repeatValidationRequiresBalancedBlocksAndBoundedNumericControls() throws {
        let item = """
        <dict>
            <key>id</key><string>itemCount</string>
            <key>labels</key><string>Items</string>
            <key>type</key><string>number</string>
            <key>minimum</key><real>0</real>
            <key>maximum</key><real>12</real>
            <key>default</key><real>4</real>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ repeat control.itemCount }}<b>{{ repeat.position }}</b>{{ endrepeat }}{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: validURL) }
        let package = try ComponentPackageLoader.load(from: validURL)
        #expect(package.repeatMaximums == ["itemCount": 12])

        let invalidURL = try makePackage(
            manifest: manifestText.replacingOccurrences(of: "<key>maximum</key><real>12</real>", with: ""),
            template: "<section {{ component.attributes }}>{{ repeat control.itemCount }}<b></b>{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidURL)
        }
    }

    @Test
    func repeatAcceptsDirectiveWhitespaceAndLimitsNestedExpansion() throws {
        let whitespaceTemplate = "{{\n repeat\t2 }}item{{ endrepeat }}"
        let expanded = try ComponentTemplateRepeater.expand(
            whitespaceTemplate,
            properties: [:],
            maximums: [:]
        )
        #expect(expanded.template == "itemitem")

        let excessiveTemplate = "{{ repeat 100 }}{{ repeat 100 }}{{ repeat 2 }}item{{ endrepeat }}{{ endrepeat }}{{ endrepeat }}"
        #expect(throws: ComponentTemplateRepeater.RepeatError.self) {
            try ComponentTemplateRepeater.expand(
                excessiveTemplate,
                properties: [:],
                maximums: [:]
            )
        }
    }

    @Test
    func textPrimitivesUseAutomaticUniqueKeysAndStoredValues() throws {
        let template = #"<h2>{{ text="Start here" }}</h2><p>{{ text }}</p><small>{{ text="Note" }}</small>"#
        let defaultContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )
        let editedContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [
                "content1": .string("Edited & ready"),
                "content2": .string("A shorter paragraph."),
                "content3": .string("Updated note")
            ],
            slots: [:]
        )
        let editorContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:],
            componentAttributes: "data-foundry-id=\"test-component\"",
            enablesEditorMarkup: true
        )

        let primitives = ComponentTemplateRenderer.textPrimitives(in: template)
        #expect(primitives.map(\.key) == ["content1", "content2", "content3"])
        let first = try #require(primitives.first)
        let paragraph = try #require(primitives.dropFirst().first)
        #expect(first.defaultValue == "Start here")
        #expect(paragraph.defaultValue.components(separatedBy: ".").count >= 3)
        #expect(ComponentTemplateRenderer.render(template, context: defaultContext).contains("Start here"))
        let edited = ComponentTemplateRenderer.render(template, context: editedContext)
        #expect(edited.contains("Edited &amp; ready"))
        #expect(edited.contains("A shorter paragraph."))
        #expect(edited.contains("Updated note"))
        let editorHTML = ComponentTemplateRenderer.render(template, context: editorContext)
        #expect(editorHTML.components(separatedBy: "data-foundry-inline-property=").count - 1 == 3)
        #expect(editorHTML.contains("data-foundry-inline-property=\"content1\""))
        #expect(editorHTML.contains("data-foundry-inline-property=\"content2\""))
        #expect(editorHTML.contains("data-foundry-inline-property=\"content3\""))
    }

    @Test
    func bareTextPrimitiveUsesOneLoremParagraphWithoutAnExportedWrapper() {
        let template = "<p>{{ text }}</p>"
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )

        let primitive = ComponentTemplateRenderer.textPrimitives(in: template)[0]
        #expect(primitive.key == "content1")
        #expect(primitive.defaultValue.components(separatedBy: ".").count >= 6)
        let rendered = ComponentTemplateRenderer.render(template, context: context)
        #expect(rendered.hasPrefix("<p>Lorem ipsum"))
        #expect(!rendered.contains("<span"))
    }

    @Test
    func textPrimitivesRenderVersionedRichTextWithoutChangingPlainTextEscaping() {
        let template = #"<p>{{ text="Start here" }}</p>"#
        let fragment = #"<strong>Hello</strong> <a href="https://example.com">world</a>"#
        let richValue = FoundryRichTextCodec.storageValue(forHTMLFragment: fragment)
        let richContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["content1": .string(richValue)],
            slots: [:],
            componentAttributes: "data-foundry-id=\"test-component\"",
            enablesEditorMarkup: true
        )
        let plainContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["content1": .string("<script>alert('no')</script>")],
            slots: [:]
        )

        let richHTML = ComponentTemplateRenderer.render(template, context: richContext)
        #expect(richHTML.contains(fragment))
        #expect(richHTML.contains("data-foundry-inline-property=\"content1\""))
        #expect(richHTML.contains("data-foundry-inline-source=\"\(Data(richValue.utf8).base64EncodedString())\""))

        let plainHTML = ComponentTemplateRenderer.render(template, context: plainContext)
        #expect(plainHTML.contains("&lt;script&gt;alert(&#39;no&#39;)&lt;/script&gt;"))
        #expect(!plainHTML.contains("<script>"))
    }

    @Test
    func richTextLinksPreserveStructureAndResolveAtRenderTime() throws {
        let pageID = UUID()
        let link = ComponentLink(
            destination: .page(pageID),
            anchor: "details",
            opensInNewWindow: true,
            attributes: [.init(name: "data-source", value: "rich text")]
        )
        let linkURL = try #require(FoundryRichTextCodec.URL(for: link))
        #expect(FoundryRichTextCodec.componentLink(from: linkURL) == link)

        let fragment = #"<a href="\#(linkURL.absoluteString)">Learn more</a>"#
        let richValue = FoundryRichTextCodec.storageValue(forHTMLFragment: fragment)
        let page = Page(id: pageID, title: "About", slug: "about")
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.rich-link",
            properties: ["content1": .string(richValue)],
            slots: [:],
            richTextLinkContext: .init(
                pages: [page],
                folders: [],
                assets: [],
                assetLibrary: [],
                publicURL: "",
                absoluteURL: false
            )
        )

        let rendered = ComponentTemplateRenderer.render(#"<p>{{ text }}</p>"#, context: context)
        #expect(rendered.contains(#"href="/about/#details""#))
        #expect(rendered.contains(#"target="_blank""#))
        #expect(rendered.contains(#"data-source="rich text""#))
        #expect(rendered.contains(#"rel="noopener noreferrer""#))
        #expect(!rendered.contains("foundry-rich-link-v1:"))
    }

    @Test
    func htmlPrimitivePreservesMarkupAndSupportsCanvasEditing() throws {
        let template = #"<div {{ component.attributes }}>{{ html="<strong>Start here</strong>" }}</div>"#
        let editorContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.html",
            properties: ["html1": .string("<em>Edited & ready</em>")], slots: [:],
            componentAttributes: "data-foundry-id=\"test-component\"",
            enablesEditorMarkup: true
        )

        let primitive = try #require(ComponentTemplateRenderer.htmlPrimitives(in: template).first)
        #expect(primitive.key == "html1")
        #expect(primitive.defaultValue == "<strong>Start here</strong>")
        let rendered = ComponentTemplateRenderer.render(template, context: editorContext)
        #expect(rendered.contains("<em>Edited & ready</em>"))
        #expect(rendered.contains("data-foundry-inline-property=\"html1\""))
        #expect(rendered.contains("data-foundry-inline-html"))
        let encodedSource = Data("<em>Edited & ready</em>".utf8).base64EncodedString()
        #expect(rendered.contains("data-foundry-inline-source=\"\(encodedSource)\""))
    }

    @Test
    func bareHTMLPrimitiveUsesAnEditableListDefault() throws {
        let primitive = try #require(ComponentTemplateRenderer.htmlPrimitives(in: "<div>{{ html }}</div>").first)

        #expect(primitive.defaultValue.contains("<ul>"))
        #expect(primitive.defaultValue.components(separatedBy: "<li>").count - 1 == 3)
    }

    @Test
    func namedImagePrimitiveRendersItsDeclaredProperty() {
        let template = "<figure {{ component.attributes }}>{{ image source }}</figure>"
        let editorContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.image",
            properties: [:], slots: [:], componentAttributes: "data-editor=\"true\"",
            enablesEditorMarkup: true
        )
        let exportContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.image",
            properties: ["source": .string("assets/hero & wide.jpg")], slots: [:]
        )

        #expect(ComponentTemplateRenderer.hasImagePrimitive(in: template))
        #expect(ComponentTemplateRenderer.render(template, context: editorContext).contains("data-foundry-image-drop-zone"))
        let exported = ComponentTemplateRenderer.render(template, context: exportContext)
        #expect(exported.contains("class=\"foundry-image\""))
        #expect(exported.contains("src=\"assets/hero &amp; wide.jpg\""))
    }

    @Test
    func imageControlMayOmitItsDefaultAndResponsiveKeys() throws {
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifest(withCustomItems: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>labels</key><string>Image</string>
                    <key>group</key><string>Content</string>
                    <key>type</key><string>image</string>
                </dict>
                """).utf8)
        )
        let image = try #require(manifest.properties.first)

        #expect(image.defaultValue == .string(""))
        #expect(!image.responsive)
    }

    @Test
    func imageMacroRequiresANamedImageProperty() throws {
        let manifestText = manifest(withCustomItems: """
            <dict>
                <key>id</key><string>title</string>
                <key>labels</key><string>Title</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>text</string>
                <key>default</key><string>Hello</string>
                <key>responsive</key><false/>
            </dict>
            """)
        let barePackage = try makePackage(
            manifest: manifestText,
            template: "<figure {{ component.attributes }}>{{ image }}</figure>"
        )
        let wrongTypePackage = try makePackage(
            manifest: manifestText,
            template: "<figure {{ component.attributes }}>{{ image title }}</figure>"
        )
        defer {
            try? FileManager.default.removeItem(at: barePackage)
            try? FileManager.default.removeItem(at: wrongTypePackage)
        }

        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: barePackage)
        }
        do {
            _ = try ComponentPackageLoader.load(from: wrongTypePackage)
            Issue.record("A text property was accepted by an image macro.")
        } catch ComponentPackageLoadingError.invalid(let diagnostics) {
            #expect(diagnostics.contains { $0.message.contains("must use the image control") })
        }
    }

    @Test
    func imageDefaultMustBeDeclaredAndResolvesThroughAssetPaths() throws {
        let validImageManifest = manifest(withCustomItems: """
            <dict>
                <key>id</key><string>source</string>
                <key>labels</key><string>Image</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>image</string>
                <key>default</key><string>images/icon.svg</string>
            </dict>
            """)
        let packageURL = try makePackage(
            manifest: validImageManifest,
            template: "<figure {{ component.attributes }}>{{ image source }}{{ slot id=\"content\" }}</figure>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        #expect(package.manifest.properties.first?.defaultValue == .string("images/icon.svg"))

        let rendered = ComponentTemplateRenderer.render(
            package.htmlTemplate,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: package.manifest.identifier,
                properties: ["source": .string("images/icon.svg")],
                slots: [:],
                assetPaths: ["images/icon.svg": "files/icon.svg"]
            )
        )
        #expect(rendered.contains("src=\"files/icon.svg\""))

        let invalidManifest = validImageManifest.replacingOccurrences(
            of: "<key>default</key><string>images/icon.svg</string>",
            with: "<key>default</key><string>images/missing.svg</string>"
        )
        let invalidPackage = try makePackage(
            manifest: invalidManifest,
            template: "<figure {{ component.attributes }}>{{ image source }}{{ slot id=\"content\" }}</figure>"
        )
        defer { try? FileManager.default.removeItem(at: invalidPackage) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidPackage)
        }
    }

    @Test
    func textPrimitivePreservesEditedLineBreaks() {
        let template = "<p>{{ text }}</p>"
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["content1": .string("First line\nSecond & final line")],
            slots: [:]
        )

        #expect(
            ComponentTemplateRenderer.render(template, context: context)
                == "<p>First line<br>Second &amp; final line</p>"
        )
    }

    @Test
    func dottedSlotSyntaxIsRejectedAndNotRendered() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<section {{ component.attributes }}>{{ slot.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.card",
            properties: [:],
            slots: ["content": "<strong>Child</strong>"]
        )

        #expect(diagnostics.contains {
            $0.severity == .error && $0.message == "Slot macros must use {{ slot id=\"…\" }}."
        })
        #expect(!ComponentTemplateRenderer.render("{{ slot.content }}", context: context).contains("Child"))
    }

    @Test
    func validatorReportsTemplateContractErrorsWithLineLocations() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: """
            <section>
              {{ control.missing }}
              {{ slot id="unknown" }}
              {{ asset.../secret.txt }}
              {{ mystery }}
              {{ if control.title }}
            </section>
            """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        let messages = diagnostics.map(\.message)

        #expect(messages.contains(where: { $0.contains("component.attributes") }))
        #expect(messages.contains(where: { $0.contains("Unknown property 'missing'") }))
        #expect(messages.contains(where: { $0.contains("Unknown slot 'unknown'") }))
        #expect(messages.contains(where: { $0.contains("Declared slot 'content'") }))
        #expect(messages.contains(where: { $0.contains("Asset paths must be relative") }))
        #expect(messages.contains(where: { $0.contains("unbalanced") }))
        #expect(messages.contains(where: { $0.contains("Unknown template macro 'mystery'") }))
        #expect(diagnostics.contains(where: { $0.location == "component.html:2" }))
    }

    @Test
    func validatorRejectsMoreThanFiveTags() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: "<key>description</key><string>A test card.</string>",
            with: """
            <key>description</key><string>A test card.</string>
            <key>tags</key>
            <array>
                <string>one</string><string>two</string><string>three</string>
                <string>four</string><string>five</string><string>six</string>
            </array>
            """
        )
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains {
            $0.location == "Info.plist:tags" && $0.message == "A component can declare at most 5 tags."
        })
    }

    @Test
    func loaderProcessesInstanceScopedCSSTemplateFiles() throws {
        let manifest = validManifest.replacingOccurrences(
            of: instanceCSSDeclaration,
            with: """
            <key>files</key>
            <array>
                <dict>
                    <key>path</key><string>instance.css</string>
                    <key>scope</key><string>instance</string>
                </dict>
                <dict>
                    <key>path</key><string>default-scope.css</string>
                </dict>
            </array>
            """
        )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section id=\"{{ id }}\" {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: [
                "instance.css": "#{{ id }} { color: red; }",
                "default-scope.css": "#{{ id }} { display: block; }"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)

        #expect(package.manifest.render.files.map(\.scope) == [.instance, .instance])
        #expect(package.css.contains("color: red"))
        #expect(package.css.contains("display: block"))
    }

    @Test
    func validatorRejectsUnimplementedTemplateScopesAndFormats() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: instanceCSSDeclaration,
            with: """
            <key>files</key>
            <array>
                <dict><key>path</key><string>component.scss</string><key>scope</key><string>instance</string></dict>
            </array>
            """
        )
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section id=\"{{ id }}\" {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["component.scss": ":host {}"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains(where: { $0.message.contains("support CSS, JavaScript, PHP and placed HTML") }))
    }

    @Test
    func loaderProcessesScopedJavaScriptTemplates() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>instance.js</string><key>scope</key><string>instance</string></dict>
            <dict><key>path</key><string>page.js</string><key>scope</key><string>page</string><key>closure</key><false/></dict>
        </array>
        """
        let manifestText = validManifest
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section id=\"{{ id }}\" {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: [
                "instance.js": "document.querySelector('#{{ id }}');",
                "page.js": "console.log('{{ package.id }} page');"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)

        #expect(package.instanceJavaScript.hasPrefix("(function (component) {"))
        #expect(package.instanceJavaScript.contains("\"use strict\";"))
        #expect(package.instanceJavaScript.contains("{{ id }}"))
        #expect(package.instanceJavaScript.contains("document.getElementById('{{ id }}')"))
        #expect(package.pageJavaScript.contains("page"))
        #expect(!package.pageJavaScript.contains("(function ()"))
    }

    @Test
    func validatorAllowsSiteScopeOnlyForCSS() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>site.js</string><key>scope</key><string>site</string></dict>
            <dict><key>path</key><string>site.php</string><key>scope</key><string>site</string></dict>
        </array>
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "<key>templates</key>", with: "<key>requiresPhp</key><true/>\n            <key>templates</key>")
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: [
                "site.js": "console.log('site');",
                "site.php": "<?php $site = true; ?>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.filter { $0.message == "Site scope is available only to CSS templates." }.count == 2)
    }

    @Test
    func staticRendererConnectsInstanceJavaScriptToItsComponentElement() throws {
        let identifier = "com.example.javascript\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>instance.js</string><key>scope</key><string>instance</string></dict>
        </array>
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section class=\"test{{ component.class }}\" {{ component.attributes }}><button>Test</button>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["instance.js": "component.querySelector('button');"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        let node = ComponentNode(type: ComponentType(rawValue: identifier))
        let site = Site(name: "JavaScript", pages: [Page(title: "Home", slug: "index", components: [node])])

        let bundle = StaticSiteRenderer().render(site: site)
        let html = try #require(bundle.file(at: "index.html")?.contents)
        let pageJavaScript = try #require(bundle.file(at: "files/page.js")?.contents)

        #expect(html.contains("id=\"foundry-\(node.id.uuidString.lowercased())\""))
        #expect(pageJavaScript.contains("document.getElementById('foundry-\(node.id.uuidString.lowercased())')"))
    }

    @Test
    func loaderProcessesScopedPHPTemplatesIntoExportedPagePrelude() throws {
        let identifier = "com.example.phptemplates\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>instance.php</string><key>scope</key><string>instance</string></dict>
            <dict><key>path</key><string>page.php</string><key>scope</key><string>page</string></dict>
        </array>
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: "<key>templates</key>", with: "<key>requiresPhp</key><true/>\n            <key>templates</key>")
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section id=\"{{ id }}\" {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: [
                "instance.php": "<?php $componentIDs[] = '{{ id }}'; ?>",
                "page.php": "<?php $package = '{{ package.id }}'; ?>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        let type = ComponentType(rawValue: identifier)
        let first = ComponentNode(type: type)
        let second = ComponentNode(type: type)
        let site = Site(name: "PHP", pages: [Page(title: "Home", slug: "index", components: [first, second])])
        let php = try #require(StaticSiteRenderer().render(site: site).file(at: "index.php")?.contents)

        #expect(package.instancePHP.contains("$componentIDs"))
        #expect(php.hasPrefix("<?php"))
        #expect(php.contains(first.id.uuidString.lowercased()))
        #expect(php.contains(second.id.uuidString.lowercased()))
        #expect(php.components(separatedBy: "$package =").count - 1 == 1)
        let doctypeRange = try #require(php.range(of: "<!doctype html>"))
        #expect(doctypeRange.lowerBound > php.startIndex)
    }

    @Test
    func validatorRequiresPhpExtensionForPHPTemplates() throws {
        let declaration = """
        <key>files</key>
        <array><dict><key>path</key><string>component.php</string></dict></array>
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["component.php": "<?php return; ?>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(manifestText.utf8))

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains { $0.location == "Info.plist:requiresPhp" })
    }

    @Test
    func textAlignmentSpecializedControlProvidesValidatedLogicalValues() throws {
        let item = """
        <dict>
            <key>id</key><string>alignment</string>
            <key>labels</key><string>Alignment</string>
            <key>group</key><string>Typography</string>
            <key>type</key><string>textAlignment</string>
            <key>default</key><string>start</string>
            <key>responsive</key><true/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }} style=\"text-align: {{ control.alignment }}\">{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(ComponentPackageAdapter.definition(from: package).properties.first { $0.key.rawValue == "alignment" })

        if case .textAlignment = property.control {} else { Issue.record("Expected the specialised text-alignment control") }
        #expect(property.defaultValue == .choice("start"))
        #expect(property.isResponsive)
    }

    @Test
    func customItemsDefaultToTheSettingsGroup() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: "<key>group</key><string>Content</string>",
            with: ""
        )

        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        #expect(manifest.properties.first?.group == "Settings")
    }

    @Test
    func selectUsingThemeValuesCannotBeAMultiControl() throws {
        let item = """
        <dict>
            <key>id</key><string>sizes</string>
            <key>labels</key><array><string>First</string><string>Second</string></array>
            <key>type</key><string>select</string>
            <key>themeValues</key><string>fontSizes</string>
            <key>count</key><integer>2</integer>
            <key>default</key><array><string>base</string><string>base</string></array>
            <key>responsive</key><false/>
        </dict>
        """
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifest(withCustomItems: item).utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains {
            $0.location == "Info.plist:customItems.sizes.count" &&
                $0.message == "A select control using themeValues cannot be a multi control; remove count."
        })
    }

    @Test
    func numberControlUnitsAreOptionalAndLimitedToThreeCharacters() throws {
        let numberItem = """
        <dict>
            <key>id</key><string>spacing</string>
            <key>labels</key><string>Spacing</string>
            <key>type</key><string>number</string>
            <key>default</key><real>12</real>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: numberItem)
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let property = try #require(manifest.properties.first)
        #expect(property.units == [""])

        let invalidText = manifestText.replacingOccurrences(
            of: "<key>type</key><string>number</string>",
            with: "<key>type</key><string>number</string><key>units</key><string>pixels</string>"
        )
        let invalidManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(invalidText.utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            invalidManifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains { $0.message == "A control unit can contain at most three characters." })
    }

    @Test
    func spacingControlsEnforceTheirFourSideContract() throws {
        let paddingItem = """
        <dict>
            <key>id</key><string>padding</string>
            <key>labels</key><array><string>Padding</string></array>
            <key>type</key><string>padding</string>
            <key>default</key>
            <array>
                <string>lg</string><string>auto</string><string>custom</string><string>none</string>
            </array>
            <key>customValue</key>
            <array><real>16</real><real>0</real><real>-8</real><real>0</real></array>
            <key>minimum</key><real>0</real>
            <key>maximum</key><real>64</real>
            <key>count</key><integer>4</integer>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: paddingItem)
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        let messages = Set(diagnostics.map(\.message))

        #expect(messages.contains("Padding always contains top, right, bottom and left values; remove count."))
        #expect(messages.contains("Use none, custom, a standard theme spacing ID."))
        #expect(messages.contains("Padding custom values cannot be negative."))
        #expect(messages.contains("Every customValue must be within the control's 0.0…64.0 range."))
    }

    @Test
    func sliderUsesContinuousDefaultStepVisualTicksAndOptionalUnits() throws {
        let sliderItem = """
        <dict>
            <key>id</key><string>opacity</string>
            <key>labels</key><string>Opacity</string>
            <key>type</key><string>slider</string>
            <key>minimum</key><real>0</real>
            <key>maximum</key><real>100</real>
            <key>ticks</key><integer>11</integer>
            <key>units</key><string>%</string>
            <key>default</key><real>50</real>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: sliderItem)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ component.attributes }}>{{ control.opacity }}{{ slot id=\"content\" }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(ComponentPackageAdapter.definition(from: package).properties.first)
        guard case .slider(let range, let step, let ticks, let unit, let showsValueField) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(range == 0...100)
        #expect(step == 0)
        #expect(ticks == 11)
        #expect(unit == "%")
        #expect(showsValueField)
    }

    @Test
    func multiSliderSupportsOneDisplayUnitPerValue() throws {
        let item = """
        <dict>
            <key>id</key><string>dimensions</string>
            <key>labels</key>
            <array><string>Width</string><string>Height</string><string>Opacity</string></array>
            <key>type</key><string>slider</string>
            <key>count</key><integer>3</integer>
            <key>units</key>
            <array><string>px</string><string>rem</string><string>%</string></array>
            <key>default</key>
            <array><real>20</real><real>4</real><real>80</real></array>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ component.attributes }}>{{ control.dimensions[0] }}{{ slot id=\"content\" }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(ComponentPackageAdapter.definition(from: package).properties.first)
        guard case .array(_, let count, _, _, let units, _) = property.control else {
            Issue.record("Expected a multi control")
            return
        }

        #expect(count == 3)
        #expect(units == ["px", "rem", "%"])
    }

    @Test
    func sliderOmittedDefaultUsesZeroOrNearestRangeBound() throws {
        let cases: [(minimum: Double, maximum: Double, expected: Double)] = [
            (-100, 100, 0),
            (10, 100, 10),
            (-100, -10, -10)
        ]

        for testCase in cases {
            let item = """
            <dict>
                <key>id</key><string>slider</string>
                <key>labels</key><string>Slider</string>
                <key>type</key><string>slider</string>
                <key>minimum</key><real>\(testCase.minimum)</real>
                <key>maximum</key><real>\(testCase.maximum)</real>
                <key>responsive</key><false/>
            </dict>
            """
            let manifestText = manifest(withCustomItems: item)
            let manifest = try PropertyListDecoder().decode(
                ComponentPackageManifest.self,
                from: Data(manifestText.utf8)
            )

            #expect(manifest.properties.first?.defaultValue == .number(testCase.expected))
        }
    }

    @Test
    func sliderCanHideItsValueField() throws {
        let item = """
        <dict>
            <key>id</key><string>slider</string>
            <key>labels</key><string>Slider</string>
            <key>type</key><string>slider</string>
            <key>showsValueField</key><false/>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ component.attributes }}>{{ control.slider }}{{ slot id=\"content\" }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(ComponentPackageAdapter.definition(from: package).properties.first)
        guard case .slider(_, _, _, _, let showsValueField) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(!showsValueField)
    }

    @Test
    func sliderStepSnapsIndependentlyOfTicks() {
        #expect(InspectorSliderValueResolver.resolve(48.020833, range: -100...100, step: 1) == 48)
        #expect(InspectorSliderValueResolver.resolve(0.86, range: 0...1, step: 0.1) == 0.9)
        #expect(InspectorSliderValueResolver.resolve(12.345, range: 0...100, step: 0) == 12.345)
        #expect(InspectorSliderValueResolver.resolve(12, range: 10...20, step: 3) == 13)
    }

    @Test
    func sliderRejectsInvalidTicksStepRangeAndUnit() throws {
        let item = """
        <dict>
            <key>id</key><string>slider</string>
            <key>labels</key><string>Slider</string>
            <key>type</key><string>slider</string>
            <key>minimum</key><real>10</real>
            <key>maximum</key><real>10</real>
            <key>step</key><real>-1</real>
            <key>ticks</key><integer>1</integer>
            <key>units</key><string>pixels</string>
            <key>default</key><real>10</real>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        let messages = Set(diagnostics.map(\.message))

        #expect(messages.contains("The control maximum must be greater than its minimum."))
        #expect(messages.contains("The control step cannot be negative."))
        #expect(messages.contains("Slider ticks must be zero or at least two."))
        #expect(messages.contains("A control unit can contain at most three characters."))
    }

    @Test
    func dividerCustomControlIsPresentationOnly() throws {
        let item = """
        <dict>
            <key>id</key><string>contentDivider</string>
            <key>group</key><string>Content</string>
            <key>type</key><string>divider</string>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(
            ComponentPackageAdapter.definition(from: package).properties.first {
                $0.key.rawValue == "contentDivider"
            }
        )
        if case .divider = property.control {} else { Issue.record("Expected a divider control") }
        #expect(!property.isResponsive)

        let invalidPackageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ control.contentDivider }}{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidPackageURL) }
        let diagnostics = ComponentPackageValidator.validate(
            package.manifest,
            rootURL: invalidPackageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        #expect(diagnostics.contains { $0.message.contains("Unknown property 'contentDivider'") })
    }

    @Test
    func loaderProcessesPageScopedHTMLPlacements() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict>
                <key>path</key><string>head.html</string>
                <key>scope</key><string>page</string>
                <key>placement</key><string>headEnd</string>
            </dict>
            <dict>
                <key>path</key><string>body.html</string>
                <key>scope</key><string>page</string>
                <key>placement</key><string>bodyEnd</string>
            </dict>
        </array>
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: [
                "head.html": "<meta name=\"package\" content=\"{{ package.id }}\">",
                "body.html": "<div data-package=\"{{ package.id }}\"></div>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)

        #expect(package.placedHTML.map(\.placement) == [.headEnd, .bodyEnd])
        #expect(package.placedHTML.first?.contents.contains("{{ package.id }}") == true)
    }

    @Test
    func loaderProcessesSiteScopedCSSAndRejectsInstanceMacrosThere() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>site.css</string><key>scope</key><string>site</string></dict>
        </array>
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["site.css": ".package-{{ package.id }} { box-sizing: border-box; }"]
        )
        defer { try? FileManager.default.removeItem(at: validURL) }

        let package = try ComponentPackageLoader.load(from: validURL)
        #expect(package.css.isEmpty)
        #expect(package.pageCSS.isEmpty)
        #expect(package.siteCSS.contains("{{ package.id }}"))

        let invalidURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["site.css": "#{{ id }} { display: none; }"]
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidURL)
        }
    }

    @Test
    func loaderProcessesPageScopedCSSAndRejectsInstanceMacrosThere() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>page.css</string><key>scope</key><string>page</string></dict>
        </array>
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["page.css": "[data-foundry-package=\"{{ package.id }}\"] { display: block; }"]
        )
        defer { try? FileManager.default.removeItem(at: validURL) }

        let package = try ComponentPackageLoader.load(from: validURL)
        #expect(package.css.isEmpty)
        #expect(package.pageCSS.contains("{{ package.id }}"))

        let invalidURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>",
            additionalFiles: ["page.css": "#{{ id }} { color: {{ control.title }}; }"]
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidURL)
        }
    }

    @Test
    func insertingIntoNamedSlotStoresTheSlotOnTheChild() throws {
        let parentID = UUID()
        var tree = [ComponentNode(id: parentID, type: .container)]
        let child = ComponentNode.make(.paragraph)

        let didInsert = tree.insert(child, at: .insideSlot(parentID, "sidebar"))

        #expect(didInsert)
        let insertedChild = try #require(tree.first?.children.first)
        #expect(insertedChild.slotID == "sidebar")
    }

    @Test @MainActor
    func builtInsAreLoadedAsPublicComponentPackages() throws {
        let catalog = ComponentPackageCatalog.shared
        let bundledPackages = catalog.packages.values.filter {
            $0.rootURL.path.contains("BuiltInComponents.bundle")
        }
        let builtIns = bundledPackages.map(ComponentPackageAdapter.definition)

        #expect(builtIns.allSatisfy { $0.renderKind == .package })
        #expect(builtIns.allSatisfy { definition in
            definition.package.map { FoundryPackLoader.isPackURL($0.rootURL) } == true
        })
        #expect(Set(builtIns.compactMap { $0.package?.manifest.identifier }).count == builtIns.count)
        #expect(ComponentType.image.definition.package?.manifest.identifier == ComponentType.image.rawValue)
        #expect(ComponentType.section.definition.package?.manifest.identifier == ComponentType.section.rawValue)
        let imageSlider = try #require(builtIns.first {
            $0.type.rawValue == "foundry.media.imageslider"
        })
        #expect(imageSlider.package?.repeatMaximums["slideCount"] == 8)
        #expect(imageSlider.properties.filter {
            if case .image = $0.control { return true }
            return false
        }.map(\.key.rawValue) == (1...8).map { "slide-\($0)" })
        #expect(ComponentType.section.definition.allowsChildren)
        #expect(!ComponentType.section.definition.properties.contains { $0.key.rawValue == "contentWidth" })
        let sectionPadding = try #require(ComponentType.section.definition.properties.first {
            $0.key.rawValue == "padding"
        })
        #expect(sectionPadding.defaultValue == .packageSpacing(.init(
            sources: ["2xl", "none", "2xl", "none"],
            customValues: [64, 0, 64, 0]
        )))
        #expect(sectionPadding.isResponsive)
        if case .packageSpacing(let kind, let range, let step) = sectionPadding.control {
            #expect(kind == .padding)
            #expect(range == 0...320)
            #expect(step == 4)
        } else {
            Issue.record("Section should use the specialised padding control")
        }
        let sectionMargin = try #require(ComponentType.section.definition.properties.first {
            $0.key.rawValue == "margin"
        })
        #expect(sectionMargin.defaultValue == .packageSpacing(.init(
            sources: ["none", "none", "none", "none"],
            customValues: [0, 0, 0, 0]
        )))
        #expect(sectionMargin.isResponsive)
        if case .packageSpacing(let kind, let range, let step) = sectionMargin.control {
            #expect(kind == .margin)
            #expect(range == -320...320)
            #expect(step == 4)
        } else {
            Issue.record("Section should use the specialised margin control")
        }
        #expect(ComponentType.image.definition.properties.contains { $0.key == .source && $0.isInspectorVisible })
        #expect(ComponentType.image.definition.properties.contains {
            $0.key.rawValue == "maxWidth" && $0.defaultValue == .number(1200) && $0.isResponsive
        })
        #expect(ComponentType.image.definition.properties.contains {
            $0.key.rawValue == "alignment" && $0.defaultValue == .choice("center") && $0.isResponsive
        })
        let bundledIdentifiers = Set(bundledPackages.map(\.manifest.identifier))
        #expect(bundledIdentifiers.isSubset(of: Set(ComponentType.allCases.map(\.rawValue))))
        let html = try #require(catalog.packages["foundry.content.html"])
        let htmlDefinition = ComponentPackageAdapter.definition(from: html)
        #expect(htmlDefinition.properties.contains { $0.key.rawValue == "html1" && !$0.isInspectorVisible })
    }

    @Test @MainActor
    func spacingControlsResolveThemeCustomAndAutomaticValuesAsCSSShorthand() {
        _ = ComponentPackageCatalog.shared
        #expect(ComponentPackageSpacingResolver.resolve(
            .init(
                sources: ["lg", ComponentThemeValueSelection.manualCustom, "none", "3xs"],
                customValues: [0, 24, 0, 0]
            ),
            theme: .standard,
            kind: .padding
        ) == "var(--foundry-space-lg) 24px 0 var(--foundry-space-3xs)")

        #expect(ComponentPackageSpacingResolver.resolve(
            .init(
                sources: [ComponentThemeValueSelection.manualCustom, "auto", "sm", "auto"],
                customValues: [-12, 0, 0, 0]
            ),
            theme: .standard,
            kind: .margin
        ) == "-12px auto var(--foundry-space-sm) auto")
    }

    @Test @MainActor
    func paragraphUsesUnifiedCustomColorWithOptInCapabilities() throws {
        _ = ComponentPackageCatalog.shared
        let properties = ComponentType.paragraph.definition.properties
        let color = try #require(properties.first(where: { $0.key.rawValue == "textColor" }))
        let alignment = try #require(properties.first(where: { $0.key.rawValue == "textAlignment" }))
        let textSize = try #require(properties.first(where: { $0.key.rawValue == "textSize" }))
        let textDecoration = try #require(properties.first(where: { $0.key.rawValue == "textDecoration" }))

        #expect(color.defaultValue == .packageColor(.init(
            source: ThemeColorRole.text.rawValue,
            customColor: "#000000",
            adjustment: 0,
            opacity: 1
        )))
        if case .packageColor(let themeValues, let colorMath, let opacity) = color.control {
            #expect(themeValues)
            #expect(colorMath)
            #expect(opacity)
        } else {
            Issue.record("Paragraph should use the package colour control")
        }
        #expect(!properties.contains { $0.key.rawValue.hasPrefix("textColor") && $0.key != color.key })
        #expect(alignment.defaultValue == .choice("start"))
        #expect(alignment.isResponsive)
        if case .textAlignment = alignment.control {} else {
            Issue.record("Paragraph should use the specialised text-alignment control")
        }
        #expect(textDecoration.defaultValue == .choice("none"))
        #expect(textDecoration.isResponsive)
        if case .choice(let choices) = textDecoration.control {
            #expect(choices.map(\.value) == ["none", "underline", "overline", "line-through"])
        } else {
            Issue.record("Paragraph should use a select control for text decoration")
        }
        #expect(textSize.defaultValue == .packageFontSize(.init(source: "base", customValue: "1rem")))
        if case .packageFontSize(let themeValues) = textSize.control {
            #expect(themeValues)
            #expect(textSize.themeValueSource == .fontSizes)
        } else {
            Issue.record("Paragraph should use a font-size theme Select")
        }
        #expect(
            ComponentType.paragraph.definition.package?.css.contains(
                "text-align: {{ control.textAlignment }}"
            ) == true
        )
        #expect(
            ComponentType.paragraph.definition.package?.css.contains(
                "line-height: {{ control.textSize.lineHeight }}"
            ) == true
        )
        #expect(
            ComponentType.paragraph.definition.package?.css.contains(
                "text-decoration-line: {{ control.textDecoration }}"
            ) == true
        )

        var paragraph = ComponentNode.make(.paragraph)
        var site = Site(name: "Line height", pages: [Page(title: "Home", slug: "index", components: [paragraph])])
        let themedHTML = HTMLPageRenderer(site: site).render(page: site.pages[0], theme: site.theme)
        #expect(themedHTML.contains("line-height: var(--foundry-font-size-base-line-height)"))

        paragraph.setProperty(
            .init(rawValue: "textSize"),
            value: .packageFontSize(.init(source: ComponentThemeValueSelection.manualCustom, customValue: "1rem", customLineHeight: "1.7"))
        )
        site.pages[0].components = [paragraph]
        let customHTML = HTMLPageRenderer(site: site).render(page: site.pages[0], theme: site.theme)
        #expect(customHTML.contains("line-height: 1.7"))

        paragraph.setProperty(.init(rawValue: "textDecoration"), value: .choice("underline"))
        site.pages[0].components = [paragraph]
        let underlinedHTML = HTMLPageRenderer(site: site).render(page: site.pages[0], theme: site.theme)
        #expect(underlinedHTML.contains("text-decoration-line: underline"))
    }

    @Test
    func packDiscoveryRecursesThroughFunctionalAndCollectionPacksWithoutFlattening() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        let nested = root.appending(path: "Nested.foundrypack", directoryHint: .isDirectory)
        let deeplyNested = nested.appending(path: "Deep.foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePackHeader(isCollection: true, at: root)
        try writePackHeader(identifier: "com.example.nested", at: nested)
        try writePackHeader(identifier: "com.example.deep", at: deeplyNested)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root, deeplyNested, nested].map(\.standardizedFileURL).sorted { $0.path < $1.path })
        #expect(try FoundryPackLoader.load(from: root).isCollection)
        #expect(!(try FoundryPackLoader.load(from: nested).isCollection))
        #expect(deeplyNested.path.hasPrefix(nested.path))
    }

    @Test
    func developmentPacksUseTheSameLoaderAndParticipateInRecursiveDiscovery() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        let nested = root.appending(path: "Nested.foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(isCollection: true, at: root)
        try writePackHeader(identifier: "com.example.development.child", at: nested)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root, nested].map(\.standardizedFileURL).sorted { $0.path < $1.path })
        #expect(try FoundryPackLoader.load(from: root).identifier == nil)
    }

    @Test
    func loadedComponentsKnowWhenTheyBelongToADevelopmentPack() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<section {{ component.attributes }}>Development{{ slot id=\"content\" }}</section>",
            pathExtension: "foundrydevpack"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)

        #expect(package.isDevelopmentPack)
    }

    @Test
    func packIdentityUsesOnlyThePublicIDKey() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        let contents = root.appending(path: "Contents", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let legacyManifest: [String: Any] = ["CFBundleIdentifier": "com.example.legacy"]
        let data = try PropertyListSerialization.data(fromPropertyList: legacyManifest, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))

        #expect(throws: FoundryPackLoadingError.self) {
            try FoundryPackLoader.load(from: root)
        }
    }

    @Test
    func manifestSchemaRejectsUnknownKeysUnsupportedAPIsAndInvalidVersions() throws {
        let cases: [(manifest: String, expected: String)] = [
            (
                validManifest.replacingOccurrences(
                    of: "<key>title</key>",
                    with: "<key>titel</key><string>Typo</string><key>title</key>"
                ),
                "Unknown key 'titel'"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "<key>minimumAPIVersion</key><integer>1</integer>",
                    with: "<key>minimumAPIVersion</key><integer>999</integer>"
                ),
                "requires Foundry component API 999"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "<key>version</key><string>1.0.0</string>",
                    with: "<key>version</key><string>1.0</string>"
                ),
                "MAJOR.MINOR.PATCH"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "<key>version</key><string>1.0.0</string>",
                    with: "<key>version</key><string>1.0.0-01</string>"
                ),
                "MAJOR.MINOR.PATCH"
            )
        ]

        for testCase in cases {
            let packageURL = try makePackage(
                manifest: testCase.manifest,
                template: "<section {{ component.attributes }}>{{ slot id=\"content\" }}</section>"
            )
            defer { try? FileManager.default.removeItem(at: packageURL) }
            do {
                _ = try ComponentPackageLoader.load(from: packageURL)
                Issue.record("The invalid manifest unexpectedly loaded.")
            } catch {
                #expect(error.localizedDescription.contains(testCase.expected))
            }
        }
    }

    @Test
    func collectionManifestSupportsOptionalUpdateMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(isCollection: true, at: root)
        #expect(try FoundryPackLoader.load(from: root).isCollection)

        let updateEnabled: [String: Any] = [
            "collection": true,
            "minimumAPIVersion": 1,
            "id": "com.example.collection",
            "title": "Collection",
            "author": "Example Developer",
            "version": "1.2.3",
            "updates": [
                "appcastURL": "https://example.com/appcast.json",
                "publicKey": Data(repeating: 1, count: 32).base64EncodedString()
            ]
        ]
        let updateData = try PropertyListSerialization.data(fromPropertyList: updateEnabled, format: .xml, options: 0)
        try updateData.write(to: root.appending(path: "Contents/Info.plist"))
        let updatePack = try FoundryPackLoader.load(from: root)
        #expect(updatePack.identifier == "com.example.collection")
        #expect(updatePack.metadata.version == "1.2.3")
        #expect(updatePack.metadata.updates?.appcastURL.absoluteString == "https://example.com/appcast.json")

        let invalid: [String: Any] = ["collection": true, "unexpected": "value"]
        let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
        try data.write(to: root.appending(path: "Contents/Info.plist"))
        #expect(throws: FoundryPackLoadingError.self) {
            try FoundryPackLoader.load(from: root)
        }
    }

    @Test
    func appcastSelectsNewestCompatibleSemanticRelease() throws {
        let releases = [
            FoundryPackAppcast.Release(
                version: "1.1.0",
                publishedAt: Date(),
                minimumAPIVersion: 1,
                downloadURL: URL(string: "https://example.com/1.1.zip")!,
                releaseNotesURL: nil,
                fileSize: 1,
                sha256: "00",
                signature: "signature"
            ),
            FoundryPackAppcast.Release(
                version: "2.0.0",
                publishedAt: Date(),
                minimumAPIVersion: 2,
                downloadURL: URL(string: "https://example.com/2.0.zip")!,
                releaseNotesURL: nil,
                fileSize: 1,
                sha256: "00",
                signature: "signature"
            )
        ]
        let appcast = FoundryPackAppcast(formatVersion: 1, packID: "com.example.pack", releases: releases)
        let release = try FoundryPackUpdateVerifier.newestRelease(
            in: appcast,
            packID: "com.example.pack",
            currentVersion: "1.0.0"
        )
        #expect(release.version == "1.1.0")
    }

    @Test
    func updateVerifierRejectsTampering() throws {
        let data = Data("release archive".utf8)
        let key = Curve25519.Signing.PrivateKey()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let release = FoundryPackAppcast.Release(
            version: "1.1.0",
            publishedAt: Date(),
            minimumAPIVersion: 1,
            downloadURL: URL(string: "https://example.com/release.zip")!,
            releaseNotesURL: nil,
            fileSize: Int64(data.count),
            sha256: digest,
            signature: try key.signature(for: data).base64EncodedString()
        )
        try FoundryPackUpdateVerifier.verify(
            data,
            release: release,
            publicKey: key.publicKey.rawRepresentation.base64EncodedString()
        )
        #expect(throws: FoundryPackUpdateError.self) {
            try FoundryPackUpdateVerifier.verify(
                Data("tampered archive".utf8),
                release: release,
                publicKey: key.publicKey.rawRepresentation.base64EncodedString()
            )
        }
    }

    @Test
    func declaredBuiltInIconLibraryIsInjectedOnlyWhenRequested() throws {
        let identifier = "com.example.icons\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "<key>templates</key>",
                with: """
                <key>libraries</key>
                <array><dict>
                    <key>id</key><string>com.foundry.icons</string>
                    <key>majorVersion</key><integer>1</integer>
                </dict></array>
                <key>templates</key>
                """
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ component.attributes }}><i class=\"bi bi-alarm\"></i>{{ slot id=\"content\" }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)

        let site = Site(
            name: "Icons",
            pages: [Page(title: "Home", slug: "index", components: [
                ComponentNode(type: ComponentType(rawValue: identifier))
            ])]
        )
        let bundle = StaticSiteRenderer().render(site: site)

        #expect(bundle.file(at: "files/site.css")?.contents.contains("bootstrap-icons") == true)
        #expect(bundle.file(at: "files/libraries/com.foundry.icons/bootstrap-icons.woff2") != nil)
    }

    @Test
    func iconControlUsesTheBuiltInIconCatalogue() throws {
        let item = """
        <dict>
            <key>id</key><string>symbol</string>
            <key>labels</key><string>Icon</string>
            <key>group</key><string>Content</string>
            <key>type</key><string>icon</string>
            <key>default</key><string>stars</string>
            <key>responsive</key><false/>
        </dict>
        """
        let manifest = manifest(withCustomItems: item).replacingOccurrences(
            of: "<key>templates</key>",
            with: """
            <key>libraries</key>
            <array><dict>
                <key>id</key><string>com.foundry.icons</string>
                <key>majorVersion</key><integer>1</integer>
            </dict></array>
            <key>templates</key>
            """
        )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<span {{ component.attributes }}><i class=\"bi bi-{{ control.symbol }}\"></i>{{ slot id=\"content\" }}</span>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(
            ComponentPackageAdapter.definition(from: package).properties.first {
                $0.key.rawValue == "symbol"
            }
        )

        if case .icon = property.control {} else { Issue.record("Expected an icon control") }
        #expect(property.defaultValue == .choice("stars"))
        #expect(FoundryWebLibraryRegistry.icons.count > 2_000)
        #expect(FoundryWebLibraryRegistry.icon(named: "stars")?.cssClass == "bi-stars")
        #expect(FoundryWebLibraryRegistry.icon(named: "bi-stars")?.name == "stars")
    }

    @Test
    func iconControlRequiresItsLibraryAndAValidDefault() throws {
        let item = """
        <dict>
            <key>id</key><string>symbol</string>
            <key>labels</key><string>Icon</string>
            <key>type</key><string>icon</string>
            <key>default</key><string>not-a-real-foundry-icon</string>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains {
            $0.message == "An icon control requires com.foundry.icons major version 1 in libraries."
        })
        #expect(diagnostics.contains {
            $0.message == "An icon default must be a valid Foundry icon name, for example stars."
        })
    }

    @Test
    func developmentPackWatcherObservesNestedFileChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        let resources = root.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let file = resources.appending(path: "component.css")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("initial".utf8).write(to: file)

        await confirmation("Nested dev-pack change is observed") { changed in
            let watcher = FoundryDevelopmentPackWatcher(rootURL: root) { changed() }
            try? await Task.sleep(for: .milliseconds(250))
            try? Data("updated".utf8).write(to: file)
            try? await Task.sleep(for: .milliseconds(700))
            withExtendedLifetime(watcher) {}
        }
    }

    @Test
    func developmentPackWatcherTreatsNestedDistributionPacksAsOpaque() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        let resources = root.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let sourceFile = resources.appending(path: "component.css")
        let childPack = resources.appending(path: "Child.foundrypack", directoryHint: .isDirectory)
        let childFile = childPack.appending(path: "Contents/Resources/child.css")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: childFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: sourceFile)
        try Data().write(to: childFile)

        let watched = Set(FoundryDevelopmentPackWatcher.watchedURLs(in: root).map(\.standardizedFileURL))

        #expect(watched.contains(sourceFile.standardizedFileURL))
        #expect(!watched.contains(childPack.standardizedFileURL))
        #expect(!watched.contains(childFile.standardizedFileURL))
    }

    private var validManifest: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>minimumAPIVersion</key><integer>1</integer>
            <key>id</key><string>com.example.card</string>
            <key>title</key><string>Card</string>
            <key>version</key><string>1.0.0</string>
            <key>description</key><string>A test card.</string>
            <key>group</key><string>Content component</string>
            <key>slots</key>
            <array>
                <dict>
                    <key>id</key><string>content</string>
                    <key>title</key><string>Content</string>
                    <key>accepts</key><array><string>*</string></array>
                    <key>minimum</key><integer>0</integer>
                </dict>
            </array>
            \(defaultCustomItemsDeclaration)
            <key>templates</key>
            <dict>
                <key>html</key><string>component.html</string>
                \(instanceCSSDeclaration)
            </dict>
            <key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>
        </dict>
        </plist>
        """
    }

    private var defaultCustomItemsDeclaration: String {
        """
        <key>customItems</key>
        <array>
            <dict>
                <key>id</key><string>title</string>
                <key>labels</key><string>Title</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>text</string>
                <key>default</key><string>Hello</string>
                <key>responsive</key><false/>
            </dict>
        </array>
        """
    }

    private func manifest(withCustomItems items: String) -> String {
        let replacement = """
        <key>customItems</key>
        <array>
            \(items)
        </array>
        """
        return validManifest.replacingOccurrences(of: defaultCustomItemsDeclaration, with: replacement)
    }

    private var instanceCSSDeclaration: String {
        """
        <key>files</key>
        <array>
            <dict>
                <key>path</key><string>component.css</string>
                <key>scope</key><string>instance</string>
            </dict>
        </array>
        """
    }

    private func makePackage(
        manifest: String,
        template: String,
        additionalFiles: [String: String] = [:],
        pathExtension: String = "foundrypack"
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(pathExtension)", directoryHint: .isDirectory)
        let resourcesURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: resourcesURL.appending(path: "images", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let files = [
            "component.html": template,
            "component.css": ":host { display: block; }",
            "icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>",
            "images/icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        ].merging(additionalFiles) { _, additional in additional }
        try Data(manifest.utf8).write(to: rootURL.appending(path: "Contents/Info.plist"))
        for (path, contents) in files {
            let fileURL = resourcesURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL)
        }
        return rootURL
    }

    private func writePackHeader(
        isCollection: Bool = false,
        identifier: String = "com.example.component",
        at rootURL: URL
    ) throws {
        let contentsURL = rootURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = isCollection
            ? ["collection": true]
            : ["id": identifier]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
    }
}
