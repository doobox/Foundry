import Foundation
import CryptoKit
import Testing
@testable import Foundry

struct ComponentPackageTests {
    @Test
    func componentValidationModesSelectTheIntendedPackKinds() {
        let releaseComponent = URL(filePath: "/Packs/Example.foundrypack/Components/Card.foundrycomponent")
        let developmentComponent = URL(filePath: "/Packs/Example.foundrydevpack/Components/Card.foundrycomponent")

        #expect(!ComponentValidationMode.off.validates(releaseComponent))
        #expect(!ComponentValidationMode.off.validates(developmentComponent))
        #expect(!ComponentValidationMode.developmentPacks.validates(releaseComponent))
        #expect(ComponentValidationMode.developmentPacks.validates(developmentComponent))
        #expect(ComponentValidationMode.allPacks.validates(releaseComponent))
        #expect(ComponentValidationMode.allPacks.validates(developmentComponent))
    }

    @Test
    func successfulValidationIsCachedButTemplateChangesAreStillValidated() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let first = try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: true)
        #expect(first.timings.semanticValidation > .zero)

        let second = try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: true)
        #expect(second.timings.semanticValidation == .zero)

        let templateURL = packageURL.appending(
            path: "Contents/Resources/\(first.package.manifest.render.html)"
        )
        try "<section {{ component.attributes }}>{{ control.missing }}</section>"
            .write(to: templateURL, atomically: true, encoding: .utf8)

        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: true)
        }
    }

    @Test
    func componentIdentifiersAllowInternalHyphensButRejectInvalidDNSLabels() throws {
        let validURL = try makePackage(
            manifest: validManifest.replacingOccurrences(
                of: "com.example.card",
                with: "com.example.focal-point-hero"
            ),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: validURL) }
        #expect(try ComponentPackageLoader.load(from: validURL).manifest.identifier == "com.example.focal-point-hero")

        for identifier in ["com.example.focal_point", "com.example.-hero", "com.example.hero-", "Com.example.hero"] {
            let invalidURL = try makePackage(
                manifest: validManifest.replacingOccurrences(of: "com.example.card", with: identifier),
                template: "<section {{ component.attributes }}>{{ control.content }}</section>"
            )
            defer { try? FileManager.default.removeItem(at: invalidURL) }
            #expect(throws: ComponentPackageLoadingError.self) {
                try ComponentPackageLoader.load(from: invalidURL)
            }
        }
    }

    @Test
    func removedControlTypesAreRejected() {
        for type in ["fontFamily", "info", "margin", "padding"] {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>type</key><string>\(type)</string>
            </dict></plist>
            """

            do {
                _ = try PropertyListDecoder().decode(
                    ComponentPackageControl.self,
                    from: Data(plist.utf8)
                )
                Issue.record("The removed \(type) control unexpectedly decoded.")
            } catch {
                // Unknown control types must fail package decoding.
            }
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
        #expect(enablePackage.manifest.identifier == "dev.foundry.enable-conditions")
        #expect(enablePackage.manifest.properties.contains { $0.enable?.id == "titles[2]" })

        let themePackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ThemeValues.foundrydevpack")
        )
        #expect(themePackage.manifest.identifier == "dev.foundry.theme-values")
        #expect(themePackage.manifest.properties.contains { $0.control.themeValueSource == .fontFamilies })
        #expect(themePackage.manifest.properties.contains {
            $0.id == "topBorder" && $0.control.type == .themeColor && $0.control.allowsCustom == true
        })
        #expect(themePackage.manifest.properties.contains {
            $0.id == "bottomBorder" && $0.control.type == .themeColor && $0.control.allowsCustom == true
        })

        let scopedAssetsPackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ScopedAssets.foundrydevpack")
        )
        #expect(scopedAssetsPackage.manifest.identifier == "dev.foundry.scoped-assets")
        #expect(scopedAssetsPackage.manifest.assets.count == 3)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .page }.count == 2)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .site }.count == 1)

        let expressionPackage = try ComponentPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ExpressionEngine.foundrydevpack")
        )
        #expect(expressionPackage.manifest.identifier == "dev.foundry.expression-engine")
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
    func linkAnchorDiscoveryIncludesOnlyComponentRootAnchors() {
        let html = """
        <section data-foundry-id="ONE" id="hero"><span id="internal-label"></span></section>
        <div id="developer-id"></div>
        <article data-foundry-id="TWO" id="contact"></article>
        """

        #expect(ComponentAnchorDiscovery.identifiers(in: html) == ["hero", "contact"])
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
        <key>tags</key><array/><key>assets</key><array/>
        <key>customItems</key><array><dict>
        <key>id</key><string>palette</string><key>label</key><string>Palette</string><key>group</key><string>Appearance</string>
        <key>subtitle</key><array><string>First</string><string>Second</string><string>Third</string><string>Fourth</string></array>
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
        #expect(property.label == "Palette")
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
        <key>tags</key><array/><key>assets</key><array/>
        <key>customItems</key><array><dict>
        <key>id</key><string>tone</string><key>label</key><string>Tone</string><key>group</key><string>Appearance</string>
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
                with: "<key>type</key><string>themeColor</string>"
            )
        let colorSchemaDiagnostics = try ComponentPackageManifestSchema.diagnostics(
            for: Data(countedThemeColor.utf8)
        )
        #expect(colorSchemaDiagnostics.contains {
            $0.location.hasSuffix(".count")
                && $0.message == "A themeColor control cannot be a multi control; remove count."
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
            <key>label</key><string>Typeface</string>
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
    func shadowIsAStandaloneThemeAwareControl() throws {
        let item = """
        <dict>
            <key>id</key><string>cardShadow</string>
            <key>label</key><string>Shadow</string>
            <key>group</key><string>Appearance</string>
            <key>type</key><string>shadow</string>
            <key>allowsCustom</key><true/>
            <key>default</key><string>md</string>
            <key>responsive</key><false/>
        </dict>
        """
        let decodedManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifest(withCustomItems: item).utf8)
        )
        let property = try #require(decodedManifest.properties.first)
        #expect(property.control.type == .shadow)
        #expect(property.control.themeValues == nil)
        #expect(property.control.themeValueSource == .shadows)
        #expect(property.control.allowsCustom == true)
        let diagnostics = ComponentPackageValidator.validate(
            decodedManifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        #expect(!diagnostics.contains {
            $0.location.contains("cardShadow") || $0.location.contains("customItems")
        })

        let legacyItem = item
            .replacingOccurrences(
                of: "<key>type</key><string>shadow</string>",
                with: "<key>type</key><string>select</string><key>themeValues</key><string>shadows</string>"
            )
        let legacyDiagnostics = try ComponentPackageManifestSchema.diagnostics(
            for: Data(manifest(withCustomItems: legacyItem).utf8)
        )
        #expect(legacyDiagnostics.contains {
            $0.location.hasSuffix(".type")
                && $0.message == "Use type shadow instead of a select control requesting shadow theme values."
        })
    }

    @Test
    func malformedControlFieldsProduceActionableSchemaDiagnostics() throws {
        let validItem = """
        <dict>
            <key>id</key><string>example</string>
            <key>label</key><string>Example</string>
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
                validItem.replacingOccurrences(of: "<key>label</key><string>Example</string>", with: "<key>label</key><array><string>Example</string></array>"),
                ":label", "label must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "<key>label</key>", with: "<key>labels</key>"),
                ":labels", "Unknown key 'labels'. Check the spelling or remove it."
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

        let withoutResponsive = validItem.replacingOccurrences(
            of: "<key>responsive</key><false/>",
            with: ""
        )
        let withoutResponsiveData = Data(manifest(withCustomItems: withoutResponsive).utf8)
        #expect(try ComponentPackageManifestSchema.diagnostics(for: withoutResponsiveData).isEmpty)
        let decoded = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: withoutResponsiveData)
        #expect(decoded.properties.first?.responsive == false)
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
        <key>assets</key><array/>
        <key>customItems</key><array>
        <dict><key>id</key><string>mode</string><key>label</key><string>Mode</string><key>type</key><string>select</string><key>options</key><array><dict><key>value</key><string>featured</string><key>title</key><string>Featured</string></dict></array><key>default</key><string>featured</string><key>responsive</key><false/></dict>
        <dict><key>id</key><string>titles</string><key>label</key><string>Titles</string><key>type</key><string>text</string><key>count</key><integer>3</integer><key>default</key><array><string>One</string><string>Two</string><string>Featured story</string></array><key>responsive</key><false/></dict>
        <dict><key>id</key><string>detail</string><key>label</key><string>Detail</string><key>type</key><string>text</string><key>default</key><string>Visible</string><key>responsive</key><false/><key>enable</key><dict><key>id</key><string>titles[2]</string><key>operation</key><string>containsInsensitive</string><key>value</key><string>featured</string></dict></dict>
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
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>customItems</key><array>
        <dict><key>id</key><string>amount</string><key>label</key><string>Amount</string><key>group</key><string>Test</string><key>type</key><string>number</string><key>default</key><real>21</real><key>responsive</key><false/></dict>
        <dict><key>id</key><string>action</string><key>label</key><string>Action</string><key>group</key><string>Test</string><key>type</key><string>button</string><key>trueValue</key><string>active</string><key>falseValue</key><string>ready</string><key>default</key><false/><key>responsive</key><false/></dict>
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
    func buttonContractSupportsOptionalLabelsSubtitlesAndValidatedMappings() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.buttons</string>
        <key>title</key><string>Buttons</string><key>description</key><string>Button contract</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>customItems</key><array>
        <dict><key>id</key><string>plain</string><key>subtitle</key><string>Optional help</string><key>type</key><string>button</string><key>default</key><false/></dict>
        <dict><key>id</key><string>mapped</string><key>type</key><string>button</string><key>buttonText</key><string>Apply</string><key>buttonIcon</key><string>bolt.fill</string><key>trueValue</key><string>active</string><key>falseValue</key><string>idle</string><key>default</key><true/></dict>
        <dict><key>id</key><string>multiple</string><key>type</key><string>button</string><key>count</key><integer>2</integer><key>subtitle</key><array><string>First</string><string>Second</string></array><key>buttonText</key><array><string>Previous</string><string>Next</string></array><key>buttonIcon</key><array><string>arrow.left</string><string>arrow.right</string></array><key>activeButtonText</key><array><string>Selected previous</string><string>Selected next</string></array><key>activeButtonIcon</key><array><string>checkmark</string><string>checkmark</string></array><key>trueValue</key><array><string>one</string><string>two</string></array><key>falseValue</key><string>off</string><key>default</key><array><true/><false/></array></dict>
        <dict><key>id</key><string>singleChoice</string><key>type</key><string>button</string><key>count</key><integer>2</integer><key>selectionMode</key><string>single</string><key>trueValue</key><array><string>first</string><string>second</string></array><key>default</key><array><false/><true/></array></dict>
        <dict><key>id</key><string>wrongDefault</string><key>type</key><string>button</string><key>default</key><string>no</string></dict>
        <dict><key>id</key><string>wrongMapping</string><key>type</key><string>button</string><key>count</key><integer>2</integer><key>selectionMode</key><string>single</string><key>trueValue</key><array><string>only-one</string></array><key>default</key><array><true/><true/></array></dict>
        </array><key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        #expect(try ComponentPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: data)
        #expect(manifest.properties[0].label.isEmpty)
        #expect(manifest.properties[0].subtitles == ["Optional help"])
        #expect(manifest.properties[1].buttonTexts == ["Apply"])
        #expect(manifest.properties[1].buttonIcons == ["bolt.fill"])
        #expect(manifest.properties[2].subtitles == ["First", "Second"])
        #expect(manifest.properties[2].buttonTexts == ["Previous", "Next"])
        #expect(manifest.properties[2].buttonIcons == ["arrow.left", "arrow.right"])
        #expect(manifest.properties[2].activeButtonTexts == ["Selected previous", "Selected next"])
        #expect(manifest.properties[2].activeButtonIcons == ["checkmark", "checkmark"])
        #expect(manifest.properties[2].control.selectionMode == nil)
        #expect(manifest.properties[3].control.selectionMode == .single)
        #expect(manifest.properties[5].control.selectionMode == .single)

        let resolved = ComponentPackageDerivedValueResolver.resolve(
            [
                "plain": .boolean(false),
                "mapped": .boolean(true),
                "multiple": .array([.boolean(true), .boolean(false)]),
                "singleChoice": .array([.boolean(false), .boolean(true)])
            ],
            properties: manifest.properties
        )
        #expect(resolved["plain"] == .boolean(false))
        #expect(resolved["mapped"] == .string("active"))
        #expect(resolved["multiple"] == .array([.string("one"), .string("off")]))
        #expect(resolved["singleChoice"] == .string("second"))

        let diagnostics = ComponentPackageValidator.validate(manifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(diagnostics.contains { $0.message == "A button control requires a Boolean default value." })
        #expect(diagnostics.contains { $0.message == "A button control array requires exactly 2 trueValue values." })
        #expect(diagnostics.contains { $0.message == "A button control using single selectionMode requires exactly one true default value." })
    }

    @Test
    func colorOutputFormatsRespectOpacityAndArrays() throws {
        let formats = [
            "hex", "hexValue", "rgb", "rgba", "rgbValues", "rgbaValues",
            "hsl", "hsla", "hslValues", "hslaValues"
        ]
        let declarations = formats.map { format in
            """
            <dict><key>id</key><string>\(format)</string><key>type</key><string>color</string><key>opacity</key><true/><key>outputFormat</key><string>\(format)</string><key>default</key><string>#FF336680</string></dict>
            """
        }.joined()
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.color-formats</string>
        <key>title</key><string>Colour formats</string><key>description</key><string>Colour output contract</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>customItems</key><array>
        \(declarations)
        <dict><key>id</key><string>defaultHex</string><key>type</key><string>color</string><key>default</key><string>#FF3366</string></dict>
        <dict><key>id</key><string>opaqueRGBA</string><key>type</key><string>color</string><key>outputFormat</key><string>rgba</string><key>default</key><string>#FF3366</string></dict>
        <dict><key>id</key><string>array</string><key>type</key><string>color</string><key>count</key><integer>2</integer><key>outputFormat</key><string>rgbValues</string><key>default</key><array><string>#FF3366</string><string>#3366CC</string></array></dict>
        </array><key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        #expect(try ComponentPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: data)
        let values = Dictionary(uniqueKeysWithValues: manifest.properties.map {
            ($0.id, $0.defaultValue)
        })
        let resolved = ComponentPackageDerivedValueResolver.resolve(values, properties: manifest.properties)

        #expect(resolved["hex"] == .string("#FF336680"))
        #expect(resolved["hexValue"] == .string("FF336680"))
        #expect(resolved["rgb"] == .string("rgb(255 51 102 / 0.502)"))
        #expect(resolved["rgba"] == .string("rgba(255, 51, 102, 0.502)"))
        #expect(resolved["rgbValues"] == .string("255, 51, 102"))
        #expect(resolved["rgbaValues"] == .string("255, 51, 102, 0.502"))
        #expect(resolved["hsl"] == .string("hsl(345 100% 60% / 0.502)"))
        #expect(resolved["hsla"] == .string("hsla(345, 100%, 60%, 0.502)"))
        #expect(resolved["hslValues"] == .string("345, 100%, 60%"))
        #expect(resolved["hslaValues"] == .string("345, 100%, 60%, 0.502"))
        #expect(resolved["defaultHex"] == .string("#FF3366"))
        #expect(resolved["opaqueRGBA"] == .string("rgba(255, 51, 102, 1)"))
        #expect(resolved["array"] == .array([
            .string("255, 51, 102"),
            .string("51, 102, 204")
        ]))
        #expect(resolved["hex.red"] == .number(255))
        #expect(resolved["hex.green"] == .number(51))
        #expect(resolved["hex.blue"] == .number(102))
        #expect(resolved["hex.alpha"] == .number(128.0 / 255.0))
        #expect(resolved["hex.hue"] == .number(345))
        #expect(resolved["hex.saturation"] == .number(100))
        #expect(resolved["hex.lightness"] == .number(60))
        #expect(resolved["hex.contrastColor"] == .string("#000000"))
        #expect(resolved["hex.relativeLuminance"] == .number(0.24586962186768263))
        #expect(resolved["hex.contrastRatioWithBlack"] == .number(5.917392437353652))
        #expect(resolved["hex.contrastRatioWithWhite"] == .number(3.5488604520188827))
        #expect(resolved["array[1].red"] == .number(51))
        #expect(resolved["array[1].blue"] == .number(204))

        let channelExpression = try ComponentTemplateExpression.parse("control.array[1].blue")
        #expect(try ComponentTemplateExpression.evaluate(
            channelExpression,
            properties: resolved,
            environment: .published
        ) == .number(204))

        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: manifest.identifier,
            properties: resolved.merging([
                "filterAmount": .number(25),
                "filterAlpha": .number(0.5),
                "mixTarget": .string("#3366CC")
            ]) { current, _ in current },
            slots: [:]
        )
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | lighten(50) }}", context: context) == "#FF99B3")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | darken(50) }}", context: context) == "#801A33")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | withAlpha(0.5) }}", context: context) == "#FF336680")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | mix('#3366CC', 25) }}", context: context) == "#CC4080")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | lighten(control.filterAmount) }}", context: context) == "#FF668C")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | withAlpha(control.filterAlpha) }}", context: context) == "#FF336680")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | mix(control.mixTarget, control.filterAmount) }}", context: context) == "#CC4080")
        #expect(ComponentTemplateRenderer.render("{{ control.defaultHex | mix(control.rgba, control.filterAmount) }}", context: context) == "#FF3366")
        #expect(ComponentTemplateRenderer.render("{{ control.rgba | darken(25) }}", context: context) == "rgba(191, 38, 77, 0.502)")
    }

    @Test
    func dateControlsUseDateOnlyValuesPartsAndFormatting() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.dates</string>
        <key>title</key><string>Dates</string><key>description</key><string>Date contract</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>customItems</key><array>
        <dict><key>id</key><string>published</string><key>type</key><string>date</string><key>minimum</key><string>2026-01-01</string><key>maximum</key><string>2026-12-31</string><key>default</key><string>2026-09-08</string></dict>
        <dict><key>id</key><string>schedule</string><key>type</key><string>date</string><key>count</key><integer>2</integer><key>default</key><array><string>2026-10-01</string><string>2026-10-20</string></array></dict>
        </array><key>templates</key><dict><key>html</key><string>component.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        #expect(try ComponentPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: data)
        #expect(manifest.properties.first?.control.minimumDate == "2026-01-01")
        #expect(manifest.properties.first?.control.maximumDate == "2026-12-31")
        let values = Dictionary(uniqueKeysWithValues: manifest.properties.map { ($0.id, $0.defaultValue) })
        let resolved = ComponentPackageDerivedValueResolver.resolve(values, properties: manifest.properties)

        #expect(resolved["published"] == .string("2026-09-08"))
        #expect(resolved["published.year"] == .number(2026))
        #expect(resolved["published.month"] == .number(9))
        #expect(resolved["published.day"] == .number(8))
        #expect(resolved["published.monthName"] == .string("September"))
        #expect(resolved["published.weekday"] == .string("Tuesday"))
        #expect(resolved["schedule[1].day"] == .number(20))

        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: manifest.identifier,
            properties: resolved.merging([
                "offsetDays": .number(7),
                "datePattern": .string("d MMMM yyyy")
            ]) { current, _ in current },
            slots: [:]
        )
        #expect(ComponentTemplateRenderer.render(
            "{{ control.published | formatDate(\"d MMMM yyyy\") }}",
            context: context
        ) == "8 September 2026")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.schedule[1] | formatDate('EEE d MMM') }}",
            context: context
        ) == "Tue 20 Oct")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.published | addDays(7) }}",
            context: context
        ) == "2026-09-15")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.published | addDays(control.offsetDays) }}",
            context: context
        ) == "2026-09-15")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.published | formatDate(control.datePattern) }}",
            context: context
        ) == "8 September 2026")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.published | addMonths(1) | formatDate('d MMMM yyyy') }}",
            context: context
        ) == "8 October 2026")

        let invalid = plist.replacingOccurrences(of: "2026-09-08", with: "2026-02-30")
        let invalidManifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(invalid.utf8))
        let diagnostics = ComponentPackageValidator.validate(invalidManifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(diagnostics.contains { $0.message == "A date control requires a real calendar date using YYYY-MM-DD." })

        let outOfRange = plist.replacingOccurrences(of: "2026-09-08", with: "2027-01-01")
        let outOfRangeManifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: Data(outOfRange.utf8))
        let rangeDiagnostics = ComponentPackageValidator.validate(outOfRangeManifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(rangeDiagnostics.contains { $0.message == "The default date is after maximum." })
    }

    @Test
    func controlValuesSupportContextualOutputEncodingFilters() {
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.encoding",
            properties: [
                "title": .string("Gary's \"<Card>\" & more"),
                "query": .string("shoes & boots/large?"),
                "website": .string("https://example.com/my products?q=red shoes&sort=new"),
                "unsafeWebsite": .string("javascript:alert(1)"),
                "enabled": .boolean(true),
                "duration": .number(300),
                "items": .array([.string("one"), .number(2), .boolean(false)])
            ],
            slots: [:]
        )

        #expect(ComponentTemplateRenderer.render(
            "{{ control.title | escapeHTML }}",
            context: context
        ) == "Gary&#39;s &quot;&lt;Card&gt;&quot; &amp; more")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.title | escapeHTMLAttribute }}",
            context: context
        ) == "Gary&#39;s &quot;&lt;Card&gt;&quot; &amp; more")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.query | encodeURIComponent }}",
            context: context
        ) == "shoes%20%26%20boots%2Flarge%3F")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.website | encodeURL }}",
            context: context
        ) == "https://example.com/my%20products?q=red%20shoes&sort=new")
        #expect(ComponentTemplateRenderer.render("{{ control.unsafeWebsite | encodeURL }}", context: context).isEmpty)
        #expect(ComponentTemplateRenderer.render("{{ control.enabled | encodeJSON }}", context: context) == "true")
        #expect(ComponentTemplateRenderer.render("{{ control.duration | encodeJSON }}", context: context) == "300")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.items | encodeJSON }}",
            context: context
        ) == "[\"one\",2,false]")
        #expect(ComponentTemplateRenderer.render(
            "{{ control.title | encodeJSON }}",
            context: context
        ) == #""Gary's \"\u003CCard\u003E\" \u0026 more""#)
        #expect(ComponentTemplateRenderer.render(
            "{{ control.title | encodeJSON | escapeHTMLAttribute }}",
            context: context
        ) == #"&quot;Gary&#39;s \&quot;\u003CCard\u003E\&quot; \u0026 more&quot;"#)
    }

    @Test
    func componentLibraryVisibilityDefaultsToShownAndCanBeHidden() throws {
        let defaultManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(defaultManifest.showsInComponentLibrary)

        let hiddenManifestText = validManifest.replacingOccurrences(
            of: "<key>templates</key>",
            with: "<key>showsInComponentLibrary</key><false/>\n            <key>templates</key>"
        )
        let hiddenManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(hiddenManifestText.utf8)
        )
        #expect(!hiddenManifest.showsInComponentLibrary)
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
        <div {{ component.attributes }}>{{ asset.images/icon.svg }}|{{ asset.shared/icons/star.svg }}|{{ path.siteAssets }}|{{ site.baseURL }}|{{ page.url }}|{{ if preview }}preview{{ elseif published }}published{{ endif }}{{ control.content }}</div>
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
            template: "<div {{ component.attributes }}><img src=\"{{ asset.images/icon.svg }}\"><img src=\"{{ asset.shared/icons/star.svg }}\">{{ control.content }}</div>",
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
    func loopRendersArbitraryMarkupAndPositionMetadata() {
        let template = """
        {{ loop 3 }}
        <span data-index="{{ loop.index }}">{{ loop.position }}/{{ loop.count }} {{ if loop.first }}first{{ elseif loop.last }}last{{ endif }}</span>
        {{ endloop }}
        """
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.loop",
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
    func nestedLoopExposesParentMetadata() {
        let template = "{{ loop 2 }}{{ loop 2 }}{{ loop.parent.position }}.{{ loop.position }};{{ endloop }}{{ endloop }}"
        let rendered = ComponentTemplateRenderer.render(
            template,
            context: .init(instanceID: UUID(), packageIdentifier: "com.example.loop", properties: [:], slots: [:])
        )

        #expect(rendered == "1.1;1.2;2.1;2.2;")
    }

    @Test
    func collectionLoopSupportsAliasesNestedCollectionsAndFiltering() {
        let template = """
        {{ loop navigation.items as item where item.visible }}
        {{ item.title }}:{{ loop item.children as child }}{{ child.title }}{{ if !loop.last }},{{ endif }}{{ endloop }};
        {{ endloop }}
        """
        let values: [ComponentPackageValue] = [
            .object([
                "title": .string("Home"),
                "visible": .boolean(true),
                "children": .array([.object(["title": .string("News")]), .object(["title": .string("About")])])
            ]),
            .object(["title": .string("Hidden"), "visible": .boolean(false), "children": .array([])])
        ]
        let rendered = ComponentTemplateRenderer.render(
            template,
            context: .init(
                instanceID: UUID(), packageIdentifier: "com.example.loop", properties: [:],
                templateValues: ["navigation.items": .array(values)], slots: [:]
            )
        )

        #expect(rendered.trimmingCharacters(in: .whitespacesAndNewlines) == "Home:News,About;")
    }

    @Test
    func reversedLoopsWorkWithCountsCollectionsAndFilters() {
        let values: [ComponentPackageValue] = [
            .object(["title": .string("First"), "visible": .boolean(true)]),
            .object(["title": .string("Hidden"), "visible": .boolean(false)]),
            .object(["title": .string("Last"), "visible": .boolean(true)])
        ]
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.loop",
            properties: [:],
            templateValues: ["pages.all": .array(values)],
            slots: [:]
        )

        let collection = ComponentTemplateRenderer.render(
            "{{ loop pages.all as page where page.visible reversed }}{{ page.title }}:{{ loop.position }}:{{ loop.first }}:{{ loop.last }};{{ endloop }}",
            context: context
        )
        let counted = ComponentTemplateRenderer.render(
            "{{ loop 4 reversed }}{{ loop.position }}{{ if !loop.last }},{{ endif }}{{ endloop }}",
            context: context
        )

        #expect(collection == "Last:2:true:false;First:1:false:true;")
        #expect(counted == "4,3,2,1")
    }

    @Test
    func navigationLoopUsesPageHierarchyVisibilityAndCurrentState() throws {
        let identifier = "com.example.navigation\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: manifest(withCustomItems: "").replacingOccurrences(of: "com.example.card", with: identifier),
            template: """
            <nav {{ component.attributes }}>{{ loop navigation.items as item }}
            <a href="{{ item.href }}">{{ item.title }}</a>
            {{ loop item.children as child }}<a href="{{ child.href }}"{{ if child.current }} aria-current="page"{{ endif }}>{{ child.title }}</a>{{ endloop }}
            {{ endloop }}{{ control.content }}</nav>
            """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)

        let home = Page(title: "Home", slug: "index")
        let hidden = Page(title: "Hidden", slug: "hidden", parentPageID: home.id, includeInNavigation: false)
        let about = Page(title: "About", slug: "about", order: 2)
        let contact = Page(title: "Contact", slug: "contact", order: 1)
        let childComponent = ComponentNode(type: .init(rawValue: identifier))
        var component = ComponentNode(type: .init(rawValue: identifier))
        component.children = [childComponent]
        let current = Page(
            title: "Current & Selected", slug: "current", components: [component], parentPageID: hidden.id
        )
        let site = Site(
            name: "Navigation",
            pages: [
                about,
                hidden,
                current,
                contact,
                home
            ]
        )
        let direct = ComponentTemplateRenderer.render(
            package.htmlTemplate,
            context: .init(
                instanceID: component.id,
                packageIdentifier: identifier,
                properties: [:],
                templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: current),
                slots: ["content": ""]
            )
        )
        #expect(direct.contains(">Home</a>"))
        let homeRange = try #require(direct.range(of: ">Home</a>"))
        let contactRange = try #require(direct.range(of: ">Contact</a>"))
        let aboutRange = try #require(direct.range(of: ">About</a>"))
        #expect(homeRange.lowerBound < contactRange.lowerBound)
        #expect(contactRange.lowerBound < aboutRange.lowerBound)
        ComponentRegistry.register(package)
        let html = try #require(
            StaticSiteRenderer(environment: .preview).render(site: site, assets: [:])
                .file(at: "hidden/current/index.html")?.contents
        )

        #expect(html.contains("href=\"/\">Home</a>"))
        #expect(html.contains("href=\"/hidden/current/\" aria-current=\"page\">Current &amp; Selected</a>"))
        #expect(!html.contains(">Hidden</a>"))
        #expect(html.contains("data-foundry-component"))
        #expect(html.contains("data-foundry-package=\"\(identifier)\""))
        #expect(html.contains("data-foundry-parent=\"\(component.id.uuidString)\""))

        let decodedHidden = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(hidden))
        #expect(decodedHidden.includeInNavigation == false)
    }

    @Test
    func controlLoopKeepsPrimitiveKeysStableAcrossCountChanges() {
        let template = """
        {{ loop control.itemCount }}<article>{{ text("card", default: "Card") }}{{ image("photo") }}</article>{{ endloop }}
        <footer>{{ text("footer", default: "Footer") }}</footer>
        """
        let maximums = ["itemCount": 4]
        let textPrimitives = ComponentTemplateRenderer.textPrimitives(in: template, loopMaximums: maximums)
        #expect(textPrimitives.map(\.key) == ["card", "footer"])
        #expect(textPrimitives.first?.isRepeated == true)
        #expect(ComponentTemplateRenderer.imagePrimitives(in: template).first?.isRepeated == true)

        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.loop",
            properties: [
                "itemCount": .number(2),
                "card": .array([.string("One"), .string("Two")]),
                "footer": .string("Footer value"),
                "photo": .array([.string("one.jpg"), .string("two.jpg")])
            ],
            slots: [:],
            loopMaximums: maximums
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
            loopMaximums: maximums
        )
        let editorHTML = ComponentTemplateRenderer.render(template, context: editorContext)
        #expect(editorHTML.contains("data-foundry-primitive-property=\"card\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"photo\""))
        #expect(editorHTML.contains("data-foundry-property-path=\"0\""))

        let empty: ComponentProperty.Value = .array([])
        let edited = empty.settingValue(
            .url("asset://chosen"),
            at: [2, 4],
            defaultLeafValue: .url("")
        )

        #expect(edited.value(at: [2, 4]) == .url("asset://chosen"))
        #expect(edited.value(at: [0, 0]) == nil)
        #expect(edited.arrayValue?.count == 3)
        #expect(edited.arrayValue?[2].arrayValue?.count == 5)
    }

    @Test
    func loopValidationRequiresBalancedBlocksAndBoundedNumericControls() throws {
        let item = """
        <dict>
            <key>id</key><string>itemCount</string>
            <key>label</key><string>Items</string>
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
            template: "<section {{ component.attributes }}>{{ loop control.itemCount reversed }}<b>{{ loop.position }}</b>{{ endloop }}{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: validURL) }
        let package = try ComponentPackageLoader.load(from: validURL)
        #expect(package.loopMaximums == ["itemCount": 12])

        let invalidURL = try makePackage(
            manifest: manifestText.replacingOccurrences(of: "<key>maximum</key><real>12</real>", with: ""),
            template: "<section {{ component.attributes }}>{{ loop control.itemCount }}<b></b>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidURL)
        }

        let legacyURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ repeat 2 }}<b></b>{{ endrepeat }}{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: legacyURL)
        }

        let invalidFilterURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ loop navigation.items as item where item.current && }}<b></b>{{ endloop }}{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidFilterURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidFilterURL)
        }
    }

    @Test
    func loopAcceptsDirectiveWhitespaceAndLimitsNestedExpansion() throws {
        let whitespaceTemplate = "{{\n loop\t2 }}item{{ endloop }}"
        let expanded = try ComponentTemplateLoop.expand(
            whitespaceTemplate,
            properties: [:],
            maximums: [:]
        )
        #expect(expanded.template == "itemitem")

        let excessiveTemplate = "{{ loop 100 }}{{ loop 100 }}{{ loop 2 }}item{{ endloop }}{{ endloop }}{{ endloop }}"
        #expect(throws: ComponentTemplateLoop.LoopError.self) {
            try ComponentTemplateLoop.expand(
                excessiveTemplate,
                properties: [:],
                maximums: [:]
            )
        }
    }

    @Test
    func textPrimitivesUseDeclaredUniqueNamesAndStoredValues() throws {
        let template = #"<h2>{{ text("heading", default: "Start here") }}</h2><p>{{ text("body") }}</p><small>{{ text("note", default: "Note") }}</small>"#
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
                "heading": .string("Edited & ready"),
                "body": .string("A shorter paragraph."),
                "note": .string("Updated note")
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
        #expect(primitives.map(\.key) == ["heading", "body", "note"])
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
        #expect(editorHTML.contains("data-foundry-inline-property=\"heading\""))
        #expect(editorHTML.contains("data-foundry-inline-property=\"body\""))
        #expect(editorHTML.contains("data-foundry-inline-property=\"note\""))
        #expect(editorHTML.components(separatedBy: "data-foundry-primitive-property=").count - 1 == 3)
        #expect(editorHTML.contains("data-foundry-primitive-property=\"heading\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"body\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"note\""))
    }

    @Test
    func namedTextPrimitiveWithoutDefaultUsesOneLoremParagraphWithoutAnExportedWrapper() {
        let template = "<p>{{ text(\"body\") }}</p>"
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )

        let primitive = ComponentTemplateRenderer.textPrimitives(in: template)[0]
        #expect(primitive.key == "body")
        #expect(primitive.defaultValue.components(separatedBy: ".").count >= 6)
        let rendered = ComponentTemplateRenderer.render(template, context: context)
        #expect(rendered.hasPrefix("<p>Lorem ipsum"))
        #expect(!rendered.contains("<span"))
    }

    @Test
    func textPrimitivesRenderVersionedRichTextWithoutChangingPlainTextEscaping() {
        let template = #"<p>{{ text("body", default: "Start here") }}</p>"#
        let fragment = #"<strong>Hello</strong> <a href="https://example.com">world</a>"#
        let richValue = FoundryRichTextCodec.storageValue(forHTMLFragment: fragment)
        let richContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["body": .string(richValue)],
            slots: [:],
            componentAttributes: "data-foundry-id=\"test-component\"",
            enablesEditorMarkup: true
        )
        let plainContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["body": .string("<script>alert('no')</script>")],
            slots: [:]
        )

        let richHTML = ComponentTemplateRenderer.render(template, context: richContext)
        #expect(richHTML.contains(fragment))
        #expect(richHTML.contains("data-foundry-inline-property=\"body\""))
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
            properties: ["body": .string(richValue)],
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

        let rendered = ComponentTemplateRenderer.render(#"<p>{{ text("body") }}</p>"#, context: context)
        #expect(rendered.contains(#"href="/about/#details""#))
        #expect(rendered.contains(#"target="_blank""#))
        #expect(rendered.contains(#"data-source="rich text""#))
        #expect(rendered.contains(#"rel="noopener noreferrer""#))
        #expect(!rendered.contains("foundry-rich-link-v1:"))
    }

    @Test
    func htmlPrimitivePreservesMarkupAndSupportsCanvasEditing() throws {
        let template = #"<div {{ component.attributes }}>{{ html("content", default: "<strong>Start here</strong>") }}</div>"#
        let editorContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.html",
            properties: ["content": .string("<em>Edited & ready</em>")], slots: [:],
            componentAttributes: "data-foundry-id=\"test-component\"",
            enablesEditorMarkup: true
        )

        let primitive = try #require(ComponentTemplateRenderer.htmlPrimitives(in: template).first)
        #expect(primitive.key == "content")
        #expect(primitive.defaultValue == "<strong>Start here</strong>")
        let rendered = ComponentTemplateRenderer.render(template, context: editorContext)
        #expect(rendered.contains("<em>Edited & ready</em>"))
        #expect(rendered.contains("data-foundry-inline-property=\"content\""))
        #expect(rendered.contains("data-foundry-inline-html"))
        let encodedSource = Data("<em>Edited & ready</em>".utf8).base64EncodedString()
        #expect(rendered.contains("data-foundry-inline-source=\"\(encodedSource)\""))
    }

    @Test
    func namedHTMLPrimitiveWithoutDefaultUsesAnEditableListDefault() throws {
        let primitive = try #require(ComponentTemplateRenderer.htmlPrimitives(in: "<div>{{ html(\"content\") }}</div>").first)

        #expect(primitive.defaultValue.contains("<ul>"))
        #expect(primitive.defaultValue.components(separatedBy: "<li>").count - 1 == 3)
    }

    @Test
    func namedImagePrimitiveRendersItsDeclaredProperty() {
        let template = "<figure {{ component.attributes }}>{{ image(\"hero\") }}</figure>"
        let editorContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.image",
            properties: [:], slots: [:], componentAttributes: "data-editor=\"true\"",
            enablesEditorMarkup: true
        )
        let exportContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.image",
            properties: ["hero": .string("assets/hero & wide.jpg")], slots: [:]
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
                    <key>label</key><string>Image</string>
                    <key>group</key><string>Content</string>
                    <key>type</key><string>image</string>
                </dict>
                """).utf8)
        )
        let image = try #require(manifest.properties.first)

        #expect(image.defaultValue == .string(""))
        #expect(!image.responsive)
        #expect(image.alt.isEmpty)
        #expect(!image.focalPoint)
        #expect(image.renditions.isEmpty)
    }

    @Test
    func imageControlSupportsStaticClampedRenditions() throws {
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifest(withCustomItems: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>type</key><string>image</string>
                    <key>renditions</key>
                    <array>
                        <dict><key>id</key><string>thumbnail</string><key>maximumDimension</key><integer>480</integer></dict>
                        <dict><key>id</key><string>hero</string><key>maximumDimension</key><integer>5000</integer></dict>
                    </array>
                </dict>
                """).utf8)
        )
        let image = try #require(manifest.properties.first)
        #expect(image.renditions.map(\.id) == ["thumbnail", "hero"])
        #expect(image.renditions.map(\.effectiveMaximumDimension) == [480, 3_840])

        let rendered = ComponentTemplateRenderer.render(
            #"<img src="{{ control.source.rendition.thumbnail.href }}">"#,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: "com.example.image",
                properties: [
                    "source": .string("assets/original.png"),
                    "source.rendition.thumbnail": .string("assets/renditions/thumb.png")
                ],
                slots: [:]
            )
        )
        #expect(rendered.contains(#"src="assets/renditions/thumb.png""#))
    }

    @Test
    func imageControlHrefResolvesDeclaredPackageAssetPaths() {
        let rendered = ComponentTemplateRenderer.render(
            #"<section style="background-image: url('{{ control.background.href }}')"></section>"#,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: "com.example.hero",
                properties: [
                    "background.href": .string("images/default.svg")
                ],
                slots: [:],
                assetPaths: [
                    "images/default.svg": "foundry-package-asset://com.example.hero/images/default.svg"
                ]
            )
        )
        #expect(rendered.contains("foundry-package-asset://com.example.hero/images/default.svg"))
    }

    @Test
    func staticExportPublishesOneSharedRenditionForRepeatedComponentUse() throws {
        let identifier = "com.example.rendition\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: manifest(withCustomItems: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>type</key><string>image</string>
                    <key>renditions</key><array>
                        <dict><key>id</key><string>thumbnail</string><key>maximumDimension</key><integer>20</integer></dict>
                    </array>
                </dict>
                """).replacingOccurrences(of: "com.example.card", with: identifier),
            template: #"<figure {{ component.attributes }}><img src="{{ control.source.rendition.thumbnail.href }}">{{ control.content }}</figure>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)

        let data = try testPNG(width: 100, height: 50)
        let asset = ProjectAsset(
            filename: "hero.png",
            mediaType: "image/png",
            byteCount: data.count,
            pixelWidth: 100,
            pixelHeight: 50
        )
        var first = ComponentNode(type: .init(rawValue: identifier))
        first.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        var second = ComponentNode(type: .init(rawValue: identifier))
        second.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        let site = Site(
            name: "Renditions",
            pages: [
                Page(title: "Home", slug: "index", components: [first]),
                Page(title: "About", slug: "about", components: [second])
            ],
            assets: [asset]
        )
        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: .init(asset: asset, data: data)]
        )
        let renditionPath = "assets/renditions/\(asset.id.uuidString.lowercased())-20.png"
        let rendition = try #require(bundle.file(at: renditionPath))
        #expect(ComponentImageMetadata.inspect(data: rendition.data, filename: "hero.png", mimeType: "image/png").width == 20)
        #expect(bundle.files.filter { $0.path == renditionPath }.count == 1)
        #expect(bundle.file(at: "index.html")?.contents.contains(renditionPath) == true)
        #expect(bundle.file(at: "about/index.html")?.contents.contains("../" + renditionPath) == true)
    }

    @Test
    func staticPreviewResolvesManagedAssetsInLoopImagePrimitives() throws {
        let identifier = "com.example.repeatedimages\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: manifest(withCustomItems: "").replacingOccurrences(of: "com.example.card", with: identifier),
            template: "<section {{ component.attributes }}>{{ loop 2 }}{{ image(\"photo\") }}{{ endloop }}{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        ComponentRegistry.register(try ComponentPackageLoader.load(from: packageURL))

        let first = ProjectAsset(filename: "first.png", mediaType: "image/png", byteCount: 1)
        let second = ProjectAsset(filename: "second.png", mediaType: "image/png", byteCount: 1)
        var component = ComponentNode(type: .init(rawValue: identifier))
        component.setProperty(
            .init(rawValue: "photo"),
            value: .array([.url(first.reference), .url(second.reference)])
        )
        let site = Site(
            name: "Repeated Images",
            pages: [Page(title: "Home", slug: "index", components: [component])],
            assets: [first, second]
        )
        let bundle = StaticSiteRenderer(environment: .preview).render(
            site: site,
            assets: [
                first.id: .init(asset: first, data: Data([0])),
                second.id: .init(asset: second, data: Data([1]))
            ]
        )
        let html = try #require(bundle.file(at: "index.html")?.contents)

        #expect(html.contains("src=\"assets/\(first.readableExportFilename)\""))
        #expect(html.contains("src=\"assets/\(second.readableExportFilename)\""))
        #expect(!html.contains("foundry-asset:"))
    }

    @Test
    func imageControlProvidesAltAndStructuredTemplateValues() throws {
        let packageURL = try makePackage(
            manifest: manifest(withCustomItems: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>group</key><string>Content</string>
                    <key>type</key><string>image</string>
                    <key>alt</key><string>Default description</string>
                    <key>focalPoint</key><true/>
                </dict>
                """),
            template: """
                <figure {{ component.attributes }}><img src="{{ control.source.href }}" width="{{ control.source.width }}" height="{{ control.source.height }}" data-type="{{ control.source.mimeType }}" data-bytes="{{ control.source.byteCount }}" data-name="{{ control.source.filename }}" data-extension="{{ control.source.extension }}" data-ratio="{{ control.source.aspectRatio }}" data-x="{{ control.source.focalPointX }}" data-y="{{ control.source.focalPointY }}" style="object-position: {{ control.source.position }}" alt="{{ control.source.alt }}">{{ control.content }}</figure>
                """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        #expect(package.manifest.properties.first?.responsive == true)
        let definitions = ComponentPackageAdapter.definition(from: package).properties
        let altDefinition = try #require(definitions.first {
            $0.key == ComponentPackageAdapter.imageAltKey(for: "source")
        })
        #expect(altDefinition.label == "Alt")
        #expect(altDefinition.defaultValue == .string("Default description"))
        #expect(!altDefinition.isResponsive)
        #expect(!altDefinition.isInspectorVisible)
        let imageDefinition = try #require(definitions.first { $0.key.rawValue == "source" })
        #expect(imageDefinition.supportsImageFocalPoint)
        #expect(!imageDefinition.isResponsive)
        let focalPointDefinition = try #require(definitions.first {
            $0.key == ComponentPackageAdapter.imageFocalPointKey(for: "source")
        })
        #expect(!focalPointDefinition.isInspectorVisible)
        #expect(focalPointDefinition.defaultValue == .array([.number(50), .number(50)]))
        #expect(focalPointDefinition.isResponsive)

        var values: [String: ComponentPackageValue] = ["source": .string("files/photo.png")]
        ComponentImageTemplateValues.insert(
            propertyID: "source",
            href: "files/photo.png",
            alt: "A <bright> photograph",
            focalPointX: 37.5,
            focalPointY: 62,
            metadata: .init(
                width: 1600,
                height: 900,
                mimeType: "image/png",
                byteCount: 42_000,
                filename: "Holiday Photo.png"
            ),
            into: &values
        )
        let rendered = ComponentTemplateRenderer.render(
            package.htmlTemplate,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: package.manifest.identifier,
                properties: values,
                slots: [:]
            )
        )
        #expect(rendered.contains("src=\"files/photo.png\""))
        #expect(rendered.contains("width=\"1600\""))
        #expect(rendered.contains("height=\"900\""))
        #expect(rendered.contains("data-type=\"image/png\""))
        #expect(rendered.contains("data-bytes=\"42000\""))
        #expect(rendered.contains("data-name=\"Holiday Photo.png\""))
        #expect(rendered.contains("data-extension=\"png\""))
        #expect(rendered.contains("data-ratio=\"1.777778\""))
        #expect(rendered.contains("data-x=\"37.5\""))
        #expect(rendered.contains("data-y=\"62\""))
        #expect(rendered.contains("object-position: 37.5% 62%"))
        #expect(rendered.contains("alt=\"A &lt;bright&gt; photograph\""))
    }

    @Test
    func imageMacroRequiresADeclaredPersistentName() throws {
        let manifestText = manifest(withCustomItems: """
            <dict>
                <key>id</key><string>title</string>
                <key>label</key><string>Title</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>text</string>
                <key>default</key><string>Hello</string>
                <key>responsive</key><false/>
            </dict>
            """)
        let barePackage = try makePackage(
            manifest: manifestText,
            template: "<figure {{ component.attributes }}>{{ image }}{{ control.content }}</figure>"
        )
        let wrongTypePackage = try makePackage(
            manifest: manifestText,
            template: "<figure {{ component.attributes }}>{{ image title }}{{ control.content }}</figure>"
        )
        defer {
            try? FileManager.default.removeItem(at: barePackage)
            try? FileManager.default.removeItem(at: wrongTypePackage)
        }

        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: barePackage)
        }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: wrongTypePackage)
        }
    }

    @Test
    func imageDefaultMustBeDeclaredAndResolvesThroughAssetPaths() throws {
        let validImageManifest = manifest(withCustomItems: """
            <dict>
                <key>id</key><string>source</string>
                <key>label</key><string>Image</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>image</string>
                <key>default</key><string>images/icon.svg</string>
            </dict>
            """)
        let packageURL = try makePackage(
            manifest: validImageManifest,
            template: "<figure {{ component.attributes }}><img src=\"{{ control.source }}\" alt=\"\">{{ control.content }}</figure>"
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
            template: "<figure {{ component.attributes }}><img src=\"{{ control.source }}\" alt=\"\">{{ control.content }}</figure>"
        )
        defer { try? FileManager.default.removeItem(at: invalidPackage) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidPackage)
        }
    }

    @Test
    func textPrimitivePreservesEditedLineBreaks() {
        let template = "<p>{{ text(\"body\") }}</p>"
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["body": .string("First line\nSecond & final line")],
            slots: [:]
        )

        #expect(
            ComponentTemplateRenderer.render(template, context: context)
                == "<p>First line<br>Second &amp; final line</p>"
        )
    }

    @Test
    func removedSlotSyntaxIsRejectedAndNotRendered() throws {
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
            $0.severity == .error
                && $0.message == "Slot macros are not supported. Declare a childPicker and render it with {{ control.id }}."
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
        #expect(messages.contains(where: { $0.contains("Slot macros are not supported") }))
        #expect(messages.contains(where: { $0.contains("childPicker 'content'") }))
        #expect(messages.contains(where: { $0.contains("Asset paths must be relative") }))
        #expect(messages.contains(where: { $0.contains("unbalanced") }))
        #expect(messages.contains(where: { $0.contains("Unknown template macro 'mystery'") }))
        #expect(diagnostics.contains(where: { $0.location == "component.html:2" }))
    }

    @Test
    func validatorRequiresNamedFunctionSyntaxForPersistentTemplateMacros() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section class="sample{{ component.class }}" {{ component.attributes }}>{{ text }}{{ html="<p>Old</p>" }}{{ image }}{{ dropZone "content" }}{{ control.content }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains { $0.contains("Every editable macro must have a permanent quoted name") })
        #expect(messages.contains { $0.contains("Every drop zone must have a permanent quoted name") })
    }

    @Test
    func validatorRequiresUniquePersistentTemplateNames() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section class="sample{{ component.class }}" {{ component.attributes }}>{{ text("shared") }}{{ image("shared") }}{{ dropZone("shared") }}{{ control.content }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains {
            $0 == "Editable macro and drop-zone names must be unique; 'shared' is used more than once."
        })
    }

    @Test
    func validatorReservesRootIDAndRequiresRootClassHook() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section id="developer-root" {{ component.attributes }}>{{ control.content }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let templateURL = packageURL.appending(path: "Contents/Resources/component.html")
        try #"<section id="developer-root" {{ component.attributes }}>{{ control.content }}</section>"#
            .write(to: templateURL, atomically: true, encoding: .utf8)
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        let messages = diagnostics.map(\.message)

        #expect(messages.contains("The component root cannot declare an id."))
        #expect(messages.contains("The root class must include {{ component.class }}."))
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
        #expect(package.instanceJavaScript.contains(#"document.querySelector('[data-foundry-id=\"{{ instance.uuid }}\"]')"#))
        #expect(package.instanceJavaScript.contains("const foundry = Object.freeze"))
        #expect(package.instanceJavaScript.contains("children: foundryChildren"))
        #expect(package.instanceJavaScript.contains("descendants: foundryDescendants"))
        #expect(package.instanceJavaScript.contains("ancestors: foundryAncestors"))
        #expect(package.instanceJavaScript.contains("closest: (packageIdentifier)"))
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            template: "<section class=\"test{{ component.class }}\" {{ component.attributes }}><button>Test</button>{{ control.content }}</section>",
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

        #expect(html.contains("data-foundry-id=\"\(node.id.uuidString)\""))
        #expect(!html.contains("id=\"foundry-"))
        #expect(pageJavaScript.contains(##"document.querySelector('[data-foundry-id=\"\##(node.id.uuidString)\"]')"##))
    }

    @Test @MainActor
    func renderersAddValidUniversalRootValuesAndOmitInvalidOnes() throws {
        let identifier = "com.example.anchor\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: identifier),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        let node = ComponentNode(
            type: ComponentType(rawValue: identifier),
            anchor: "contact-us",
            customClasses: "featured wide",
            rootAttributes: [.init(name: "aria-label", value: "Contact & help")]
        )
        let invalidNode = ComponentNode(
            type: ComponentType(rawValue: identifier),
            anchor: "123 invalid!",
            rootAttributes: [
                .init(name: "onclick", value: "alert(1)"),
                .init(name: "data-foundry-test", value: "reserved")
            ]
        )
        let site = Site(
            name: "Anchor",
            pages: [Page(title: "Home", slug: "index", components: [node, invalidNode])]
        )
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        let canvasHTML = HTMLPageRenderer().render(page: site.pages[0], theme: .standard)

        #expect(html.contains("data-foundry-id=\"\(node.id.uuidString)\""))
        #expect(html.contains("id=\"contact-us\""))
        #expect(html.contains("featured wide"))
        #expect(html.contains("aria-label=\"Contact &amp; help\""))
        #expect(html.contains("data-foundry-id=\"\(invalidNode.id.uuidString)\""))
        #expect(!html.contains("id=\"123 invalid!\""))
        #expect(!html.contains("onclick="))
        #expect(!html.contains("data-foundry-test="))
        #expect(canvasHTML.contains("id=\"contact-us\""))
        #expect(!canvasHTML.contains("id=\"123 invalid!\""))
    }

    @Test
    func manifestRejectsRemovedAnchorOptInKey() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: "<key>minimumAPIVersion</key>",
            with: "<key>anchor</key><true/>\n            <key>minimumAPIVersion</key>"
        )
        let diagnostics = try ComponentPackageManifestSchema.diagnostics(for: Data(manifestText.utf8))

        #expect(diagnostics.contains { $0.location == "Info.plist:anchor" && $0.message.contains("Unknown key") })
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            <key>label</key><string>Alignment</string>
            <key>group</key><string>Typography</string>
            <key>type</key><string>textAlignment</string>
            <key>default</key><string>start</string>
            <key>responsive</key><true/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }} style=\"text-align: {{ control.alignment }}\">{{ control.content }}</section>"
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
            <key>label</key><string>Font sizes</string>
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
            <key>label</key><string>Spacing</string>
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
    func sliderUsesContinuousDefaultStepVisualTicksAndOptionalUnits() throws {
        let sliderItem = """
        <dict>
            <key>id</key><string>opacity</string>
            <key>label</key><string>Opacity</string>
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
            template: "<output {{ component.attributes }}>{{ control.opacity }}{{ control.content }}</output>"
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
            <key>label</key><string>Dimensions</string>
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
            template: "<output {{ component.attributes }}>{{ control.dimensions[0] }}{{ control.content }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try ComponentPackageLoader.load(from: packageURL)
        let property = try #require(ComponentPackageAdapter.definition(from: package).properties.first)
        guard case .array(_, let count, _, _, _, _, _, _, let units, _) = property.control else {
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
                <key>label</key><string>Slider</string>
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
            <key>label</key><string>Slider</string>
            <key>type</key><string>slider</string>
            <key>showsValueField</key><false/>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ component.attributes }}>{{ control.slider }}{{ control.content }}</output>"
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
            <key>label</key><string>Slider</string>
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
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
            template: "<section {{ component.attributes }}>{{ control.contentDivider }}{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidPackageURL) }
        let diagnostics = ComponentPackageValidator.validate(
            package.manifest,
            rootURL: invalidPackageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        #expect(diagnostics.contains { $0.message.contains("Unknown property 'contentDivider'") })

        let unsupportedKeys = ["label", "subtitle", "toolTip", "default", "responsive", "count"]
        for key in unsupportedKeys {
            let value: String
            switch key {
            case "responsive": value = "<true/>"
            case "count": value = "<integer>2</integer>"
            default: value = "<string>Unsupported</string>"
            }
            let invalidItem = """
            <dict>
                <key>id</key><string>divider</string>
                <key>type</key><string>divider</string>
                <key>\(key)</key>\(value)
            </dict>
            """
            let schemaDiagnostics = try ComponentPackageManifestSchema.diagnostics(
                for: Data(manifest(withCustomItems: invalidItem).utf8)
            )
            #expect(schemaDiagnostics.contains { $0.message == "A divider control does not support \(key)." })
        }
    }

    @Test
    func noteCustomControlUsesDedicatedContentKeys() throws {
        let validItem = """
        <dict>
            <key>id</key><string>guidance</string>
            <key>type</key><string>note</string>
            <key>title</key><string>About this setting</string>
            <key>body</key><string>Helpful guidance.</string>
            <key>systemImage</key><string>info.circle</string>
        </dict>
        """
        let validData = Data(manifest(withCustomItems: validItem).utf8)
        #expect(try ComponentPackageManifestSchema.diagnostics(for: validData).isEmpty)

        let decodedManifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: validData)
        let property = try #require(decodedManifest.properties.first)
        #expect(property.noteTitle == "About this setting")
        #expect(property.noteBody == "Helpful guidance.")
        #expect(property.noteSystemImage == "info.circle")
        #expect(property.label.isEmpty)
        #expect(property.subtitles.isEmpty)
        #expect(!property.responsive)
        #expect(property.control.count == nil)

        let unsupportedKeys = ["label", "subtitle", "responsive", "count"]
        for key in unsupportedKeys {
            let value = switch key {
            case "responsive": "<true/>"
            case "count": "<integer>2</integer>"
            default: "<string>Unsupported</string>"
            }
            let item = """
            <dict>
                <key>id</key><string>guidance</string>
                <key>type</key><string>note</string>
                <key>body</key><string>Helpful guidance.</string>
                <key>\(key)</key>\(value)
            </dict>
            """

            let diagnostics = try ComponentPackageManifestSchema.diagnostics(
                for: Data(manifest(withCustomItems: item).utf8)
            )

            #expect(diagnostics.contains {
                $0.location == "Info.plist:customItems[0]:\(key)" &&
                    $0.message == "A note control does not support \(key)."
            })
        }

        let missingBodyItem = """
        <dict>
            <key>id</key><string>guidance</string>
            <key>type</key><string>note</string>
        </dict>
        """
        let missingBodyDiagnostics = try ComponentPackageManifestSchema.diagnostics(
            for: Data(manifest(withCustomItems: missingBodyItem).utf8)
        )
        #expect(missingBodyDiagnostics.contains {
            $0.location == "Info.plist:customItems[0]:body" &&
                $0.message == "A body string is required."
        })
    }

    @Test
    func linkControlRejectsCountAndResponsive() throws {
        for key in ["count", "responsive"] {
            let value = key == "count" ? "<integer>2</integer>" : "<true/>"
            let item = """
            <dict>
                <key>id</key><string>destination</string>
                <key>type</key><string>link</string>
                <key>label</key><string>Destination</string>
                <key>default</key><string></string>
                <key>\(key)</key>\(value)
            </dict>
            """

            let diagnostics = try ComponentPackageManifestSchema.diagnostics(
                for: Data(manifest(withCustomItems: item).utf8)
            )

            #expect(diagnostics.contains {
                $0.location == "Info.plist:customItems[0]:\(key)" &&
                    $0.message == "A link control does not support \(key)."
            })
        }
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
            additionalFiles: ["site.css": ".package-{{ package.id }} { box-sizing: border-box; }"]
        )
        defer { try? FileManager.default.removeItem(at: validURL) }

        let package = try ComponentPackageLoader.load(from: validURL)
        #expect(package.css.isEmpty)
        #expect(package.pageCSS.isEmpty)
        #expect(package.siteCSS.contains("{{ package.id }}"))

        let invalidURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
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
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
            additionalFiles: ["page.css": "[data-foundry-package=\"{{ package.id }}\"] { display: block; }"]
        )
        defer { try? FileManager.default.removeItem(at: validURL) }

        let package = try ComponentPackageLoader.load(from: validURL)
        #expect(package.css.isEmpty)
        #expect(package.pageCSS.contains("{{ package.id }}"))

        let invalidURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ component.attributes }}>{{ control.content }}</section>",
            additionalFiles: ["page.css": "#{{ id }} { color: {{ control.title }}; }"]
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: invalidURL)
        }
    }

    @Test
    func insertingThroughChildPickerStoresItsIdentifierOnTheChild() throws {
        let packageURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: "com.example.named-slot-parent"),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        defer { ComponentRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let parentID = UUID()
        var tree = [ComponentNode(id: parentID, type: ComponentType(rawValue: package.manifest.identifier))]
        let child = ComponentNode.make(.paragraph)

        let didInsert = tree.insert(child, at: .insideSlot(parentID, "content"))

        #expect(didInsert)
        let insertedChild = try #require(tree.first?.children.first)
        #expect(insertedChild.slotID == "content")
    }

    @Test
    func childPickersEnforceAcceptedTypesMaximumAndLockedContainment() throws {
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: "com.example.managed-parent")
            .replacingOccurrences(of: "<key>label</key><string>Content</string>", with: "<key>label</key><string>Cards</string>")
            .replacingOccurrences(
                of: "<key>accepts</key><array><string>*</string></array>",
                with: "<key>accepts</key><array><string>foundry.content.paragraph</string></array><key>initial</key><array><string>foundry.content.paragraph</string></array><key>minimum</key><integer>1</integer><key>maximum</key><integer>2</integer><key>containment</key><string>locked</string>"
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        defer { ComponentRegistry.unregisterPackage(identifier: package.manifest.identifier) }

        let parentID = UUID()
        let firstID = UUID()
        var tree = [ComponentNode(
            id: parentID,
            type: ComponentType(rawValue: package.manifest.identifier),
            children: [ComponentNode(id: firstID, type: .paragraph, slotID: "content")]
        )]

        let insertedButton = tree.insert(ComponentNode.make(.button), at: .insideSlot(parentID, "content"))
        let insertedSecondParagraph = tree.insert(ComponentNode.make(.paragraph), at: .insideSlot(parentID, "content"))
        let insertedThirdParagraph = tree.insert(ComponentNode.make(.paragraph), at: .insideSlot(parentID, "content"))
        let movedOutside = tree.moveNode(withID: firstID, to: .end)
        let reorderedInside = tree.moveNode(withID: firstID, to: .insideSlot(parentID, "content"))

        #expect(!insertedButton)
        #expect(insertedSecondParagraph)
        #expect(!insertedThirdParagraph)
        #expect(!movedOutside)
        #expect(reorderedInside)
    }

    @Test
    func childPickerCreatesInitialChildrenRecursively() throws {
        let grandchildIdentifier = "com.example.initial-grandchild"
        let childIdentifier = "com.example.initial-child"
        let parentIdentifier = "com.example.initial-parent"
        let acceptsDeclaration = "<key>accepts</key><array><string>*</string></array>"

        let grandchildURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: grandchildIdentifier),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: grandchildURL) }
        let grandchildPackage = try ComponentPackageLoader.load(from: grandchildURL)
        ComponentRegistry.register(grandchildPackage)
        defer { ComponentRegistry.unregisterPackage(identifier: grandchildIdentifier) }

        let childInitial = """
        \(acceptsDeclaration)
        <key>pickerItems</key>
        <array><string>\(grandchildIdentifier)</string></array>
        <key>initial</key>
        <array>
            <string>\(grandchildIdentifier)</string>
            <string>\(grandchildIdentifier)</string>
        </array>
        """
        let childURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: childIdentifier)
                .replacingOccurrences(of: acceptsDeclaration, with: childInitial),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: childURL) }
        let childPackage = try ComponentPackageLoader.load(from: childURL)
        ComponentRegistry.register(childPackage)
        defer { ComponentRegistry.unregisterPackage(identifier: childIdentifier) }

        let parentInitial = """
        \(acceptsDeclaration)
        <key>pickerItems</key>
        <array><string>\(childIdentifier)</string></array>
        <key>initial</key>
        <array>
            <string>\(childIdentifier)</string>
            <string>\(grandchildIdentifier)</string>
            <string>\(childIdentifier)</string>
        </array>
        """
        let parentURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
                .replacingOccurrences(of: acceptsDeclaration, with: parentInitial),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: parentURL) }
        let parentPackage = try ComponentPackageLoader.load(from: parentURL)
        ComponentRegistry.register(parentPackage)
        defer { ComponentRegistry.unregisterPackage(identifier: parentIdentifier) }

        let parent = ComponentNode.make(ComponentType(rawValue: parentIdentifier))

        #expect(parent.children.map(\.type.rawValue) == [
            childIdentifier,
            grandchildIdentifier,
            childIdentifier
        ])
        #expect(parent.children.allSatisfy { $0.slotID == "content" })
        #expect(parent.children.first?.children.map(\.type.rawValue) == [
            grandchildIdentifier,
            grandchildIdentifier
        ])
        #expect(parent.children.first?.children.allSatisfy { $0.slotID == "content" } == true)
    }

    @Test
    func childPickerCanOfferFewerTypesThanItAccepts() throws {
        let childIdentifier = "com.example.picker-child"
        let parentIdentifier = "com.example.picker-parent"
        let acceptsDeclaration = "<key>accepts</key><array><string>*</string></array>"
        let pickerDeclaration = """
        \(acceptsDeclaration)
        <key>pickerItems</key>
        <array><string>\(childIdentifier)</string></array>
        """
        let parentURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
                .replacingOccurrences(of: acceptsDeclaration, with: pickerDeclaration),
            template: "<section {{ component.attributes }}>{{ control.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: parentURL) }
        let parentPackage = try ComponentPackageLoader.load(from: parentURL)
        let slot = try #require(parentPackage.manifest.slots.first)

        #expect(slot.acceptsComponent(.paragraph))
        #expect(!slot.offersInPicker(.paragraph))
        #expect(slot.offersInPicker(ComponentType(rawValue: childIdentifier)))
    }

    @Test
    func childPickerValidatesInitialChildren() throws {
        let wrongShape = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>*</string></array><key>initial</key><integer>2</integer>"
        )
        let invalidValues = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>com.example.child</string></array><key>pickerItems</key><array><string>Invalid</string><string>com.example.child</string></array><key>initial</key><array><string>com.example.child</string><string>com.example.other</string></array><key>maximum</key><integer>1</integer>"
        )

        let wrongShapeDiagnostics = try ComponentPackageManifestSchema.diagnostics(for: Data(wrongShape.utf8))
        let invalidValueDiagnostics = try ComponentPackageManifestSchema.diagnostics(for: Data(invalidValues.utf8))

        #expect(wrongShapeDiagnostics.contains { $0.location.contains("initial") && $0.message.contains("strings") })
        #expect(invalidValueDiagnostics.contains { $0.location.contains("pickerItems[0]") })
        #expect(invalidValueDiagnostics.contains { $0.location.contains("initial") && $0.message.contains("maximum") })
        #expect(invalidValueDiagnostics.contains { $0.location.contains("initial[1]") && $0.message.contains("permitted") })
    }

    @Test
    func childPickerContainmentDefaultsToOpenAndDecodesLocked() throws {
        let openManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(openManifest.slots.first?.containment == .open)

        let lockedText = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>*</string></array><key>containment</key><string>locked</string>"
        )
        let lockedManifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(lockedText.utf8)
        )
        #expect(lockedManifest.slots.first?.containment == .locked)
    }

    @Test
    func childPickerAddPresentationIsOwnedByFoundry() throws {
        let manifest = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>*</string></array><key>buttonText</key><string>Add Card</string>"
        )

        let diagnostics = try ComponentPackageManifestSchema.diagnostics(for: Data(manifest.utf8))

        #expect(diagnostics.contains {
            $0.location.contains("buttonText")
                && $0.message == "A childPicker control does not support buttonText."
        })
    }

    @Test
    func dropZoneCreatesAnOrdinaryUnslottedChildArea() throws {
        let identifier = "com.example.drop-zone-parent"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration, with: "")
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section class=\"container{{ component.class }}\" {{ component.attributes }}>{{ dropzone(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try ComponentPackageLoader.load(from: packageURL)
        ComponentRegistry.register(package)
        defer { ComponentRegistry.unregisterPackage(identifier: identifier) }

        let parentID = UUID()
        var tree = [ComponentNode(id: parentID, type: ComponentType(rawValue: identifier))]
        let child = ComponentNode(type: ComponentType(rawValue: "com.example.any-child"))

        #expect(package.hasDropZone)
        #expect(ComponentPackageAdapter.definition(from: package).allowsChildren)
        let inserted = tree.insert(child, at: .inside(parentID))
        #expect(inserted)
        #expect(tree.node(withID: child.id)?.slotID == package.dropZoneSlotID(for: "content"))
    }

    @Test
    func removedNamedDropZonePreservesItsChildrenUntilTheNameReturns() throws {
        let identifier = "com.example.updated-drop-zone-parent"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration, with: "")
        let originalURL = try makePackage(
            manifest: manifest,
            template: "<main class=\"layout{{ component.class }}\" {{ component.attributes }}>{{ dropZone(\"content\") }}{{ dropZone(\"sidebar\") }}</main>"
        )
        let updatedURL = try makePackage(
            manifest: manifest,
            template: "<main class=\"layout{{ component.class }}\" {{ component.attributes }}>{{ dropZone(\"content\") }}</main>"
        )
        defer {
            ComponentRegistry.unregisterPackage(identifier: identifier)
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: updatedURL)
        }

        let originalPackage = try ComponentPackageLoader.load(from: originalURL)
        ComponentRegistry.register(originalPackage)
        let parentID = UUID()
        let child = ComponentNode(type: ComponentType(rawValue: "com.example.sidebar-child"))
        var tree = [ComponentNode(id: parentID, type: ComponentType(rawValue: identifier))]
        let inserted = tree.insert(
            child,
            at: .insideSlot(parentID, originalPackage.dropZoneSlotID(for: "sidebar"))
        )
        #expect(inserted)

        let updatedPackage = try ComponentPackageLoader.load(from: updatedURL)
        ComponentRegistry.register(updatedPackage)
        let preservedSlotID = tree.node(withID: child.id)?.slotID
        #expect(preservedSlotID == LoadedComponentPackage.dropZoneSlotPrefix + "sidebar")
        #expect(updatedPackage.isDropZoneSlotID(preservedSlotID ?? "") == false)
        #expect(LoadedComponentPackage.dropZoneName(forSlotID: preservedSlotID ?? "") == "sidebar")
        #expect(tree.node(withID: child.id) != nil)

        ComponentRegistry.register(originalPackage)
        #expect(originalPackage.isDropZoneSlotID(tree.node(withID: child.id)?.slotID ?? ""))
    }

    @Test
    func allowedParentsRestrictsChildPlacement() throws {
        let parentIdentifier = "com.example.allowed-parent"
        let childIdentifier = "com.example.restricted-child"
        let parentManifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration, with: "")
        let childManifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: childIdentifier)
            .replacingOccurrences(
                of: "<key>title</key><string>Card</string>",
                with: "<key>title</key><string>Card</string><key>allowedParents</key><array><string>\(parentIdentifier)</string></array>"
            )
        let parentURL = try makePackage(
            manifest: parentManifest,
            template: "<section class=\"container{{ component.class }}\" {{ component.attributes }}>{{ dropZone(\"content\") }}</section>"
        )
        let childURL = try makePackage(
            manifest: childManifest,
            template: "<article class=\"card{{ component.class }}\" {{ component.attributes }}>{{ control.content }}</article>"
        )
        defer {
            try? FileManager.default.removeItem(at: parentURL)
            try? FileManager.default.removeItem(at: childURL)
        }
        let parentPackage = try ComponentPackageLoader.load(from: parentURL)
        let childPackage = try ComponentPackageLoader.load(from: childURL)
        ComponentRegistry.register(parentPackage)
        ComponentRegistry.register(childPackage)
        defer {
            ComponentRegistry.unregisterPackage(identifier: parentIdentifier)
            ComponentRegistry.unregisterPackage(identifier: childIdentifier)
        }

        let parentID = UUID()
        let child = ComponentNode.make(ComponentType(rawValue: childIdentifier))
        var tree = [ComponentNode(id: parentID, type: ComponentType(rawValue: parentIdentifier))]

        #expect(!tree.accepts(child, at: .end))
        let inserted = tree.insert(child, at: .inside(parentID))
        #expect(inserted)
    }

    @Test @MainActor
    func builtInsAreLoadedAsPublicComponentPackages() async throws {
        let catalog = ComponentPackageCatalog.shared
        await catalog.waitUntilLoaded()
        #expect(catalog.phase == .ready)
        #expect(!catalog.isInitialLoading)
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
        #expect(imageSlider.package?.loopMaximums["slideCount"] == 8)
        #expect(imageSlider.properties.filter {
            if case .image = $0.control { return true }
            return false
        }.map(\.key.rawValue) == (1...8).map { "slide-\($0)" })
        #expect(ComponentType.section.definition.allowsChildren)
        #expect(!ComponentType.section.definition.properties.contains { $0.key.rawValue == "contentWidth" })
        #expect(!ComponentType.section.definition.properties.contains { ["padding", "margin"].contains($0.key.rawValue) })
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
        #expect(htmlDefinition.properties.contains { $0.key.rawValue == "content" && !$0.isInspectorVisible })
    }

    @Test @MainActor
    func installedStressComponentCatalogLoadTime() async throws {
        let installedRoot = try FoundryPackLoader.installedPacksURL()
        let stressPackURL = installedRoot.appending(
            path: "FoundryStressTest.foundrypack",
            directoryHint: .isDirectory
        )
        guard FileManager.default.fileExists(atPath: stressPackURL.path) else {
            print("Stress benchmark skipped because FoundryStressTest.foundrypack is not installed.")
            return
        }
        let expectedCount = FoundryPackLoader.packURLs(in: stressPackURL, includingRoot: true)
            .filter { $0.pathExtension.lowercased() == "foundrypack" }
            .count - 1

        let stressComponentURLs = FoundryPackLoader.packURLs(in: stressPackURL, includingRoot: true)
            .filter {
                $0.pathExtension.lowercased() == "foundrypack"
                    && $0.standardizedFileURL != stressPackURL.standardizedFileURL
            }
        let catalog = ComponentPackageCatalog.shared
        await catalog.waitUntilLoaded()
        let profileStart = ContinuousClock.now
        let measuredTimings = await withTaskGroup(of: (Int, ComponentPackageLoadTimings?).self) { group in
            var results = Array<ComponentPackageLoadTimings?>(repeating: nil, count: stressComponentURLs.count)
            let workerCount = min(4, stressComponentURLs.count)
            for index in 0..<workerCount {
                group.addTask {
                    (index, try? ComponentPackageLoader.loadWithDiagnostics(from: stressComponentURLs[index]).timings)
                }
            }
            var nextIndex = workerCount
            for await (index, timings) in group {
                results[index] = timings
                if nextIndex < stressComponentURLs.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (index, try? ComponentPackageLoader.loadWithDiagnostics(from: stressComponentURLs[index]).timings)
                    }
                }
            }
            return results.compactMap { $0 }.reduce(ComponentPackageLoadTimings(), +)
        }
        let profileElapsed = profileStart.duration(to: .now)
        func seconds(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds) + Double(components.attoseconds) / 1e18
        }
        let measuredWork = seconds(measuredTimings.total)
        let validationWork = seconds(measuredTimings.validation)
        let validationPercentage = measuredWork > 0 ? validationWork / measuredWork * 100 : 0
        print("""
        Profiled \(stressComponentURLs.count) stress components in \(profileElapsed):
          manifest reads: \(seconds(measuredTimings.manifestRead))s
          schema validation: \(seconds(measuredTimings.schemaValidation))s
          manifest decoding: \(seconds(measuredTimings.manifestDecoding))s
          semantic validation: \(seconds(measuredTimings.semanticValidation))s
          resource loading: \(seconds(measuredTimings.resourceLoading))s
          validation total: \(validationWork)s (\(validationPercentage)% of measured package work)
        """)

        let clock = ContinuousClock()
        let start = clock.now
        let validationMode = ComponentValidationPreference.mode
        catalog.reloadAllPacks()
        await catalog.waitUntilLoaded()
        let elapsed = start.duration(to: clock.now)
        let estimatedValidationWallTime = seconds(profileElapsed) * validationPercentage / 100
        let loadedCount = catalog.packages.keys.filter {
            $0.hasPrefix("foundry.stress.component")
        }.count

        print("Loaded and published \(loadedCount) stress components in \(elapsed).")
        print("Catalog validation mode: \(validationMode.rawValue).")
        if validationMode == .allPacks {
            let validationShare = estimatedValidationWallTime / seconds(elapsed) * 100
            print("Estimated validation share of this catalog load: \(validationShare)% (\(estimatedValidationWallTime)s).")
        } else {
            let estimatedValidatedLoadTime = seconds(elapsed) + estimatedValidationWallTime
            let potentialValidationShare = estimatedValidationWallTime / estimatedValidatedLoadTime * 100
            print("Estimated validation cost avoided: \(estimatedValidationWallTime)s (\(potentialValidationShare)% of an estimated validated load).")
        }
        #expect(loadedCount == expectedCount)
        #expect(elapsed < .seconds(20), "The installed stress catalog should reload within 20 seconds.")
    }

    @Test
    func catalogIndexRestoresPreparedDefinitionsWithoutLoadingRuntimePayloads() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<div {{ component.attributes }}>{{ text(\"content\", default: \"Cached text\") }}</div>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let initial = try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: false)
        #expect(!initial.package.isPayloadLoaded)
        #expect(ComponentPackageAdapter.definition(from: initial.package).properties.contains {
            $0.defaultValue == .string("Cached text")
        })
        #expect(!initial.package.isPayloadLoaded)
        ComponentPackagePreparedIndex.flush()

        let cached = try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: false)
        #expect(cached.timings.total == .zero)
        #expect(!cached.package.isPayloadLoaded)
        #expect(cached.package.htmlTemplate.contains("Cached text"))
        #expect(cached.package.isPayloadLoaded)
    }

    @Test
    func lazyPayloadFailureIsTransactionalAndRecoversAfterReload() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<div {{ component.attributes }}>Recoverable</div>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let cssURL = packageURL.appending(path: "Contents/Resources/component.css")
        let originalCSS = try Data(contentsOf: cssURL)
        let package = try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: false).package
        try FileManager.default.removeItem(at: cssURL)

        #expect(throws: ComponentPackagePayloadFailure.self) {
            try package.preparePayload()
        }
        #expect(!package.isPayloadLoaded)
        #expect(package.payloadFailure?.location == "Contents/Resources/component.css")

        try originalCSS.write(to: cssURL)
        let reloaded = try ComponentPackageLoader.loadForCatalog(from: packageURL, validates: false).package
        try reloaded.preparePayload()
        #expect(reloaded.isPayloadLoaded)
        #expect(reloaded.css.contains("display: block"))
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
            source: ComponentThemeValueSelection.manualCustom,
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
            template: "<section {{ component.attributes }}>Development{{ control.content }}</section>",
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
                template: "<section {{ component.attributes }}>{{ control.content }}</section>"
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
                    <key>id</key><string>bootstrapIcons</string>
                    <key>majorVersion</key><integer>1</integer>
                </dict></array>
                <key>templates</key>
                """
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ component.attributes }}><i class=\"bi bi-alarm\"></i>{{ control.content }}</section>"
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
        #expect(bundle.file(at: "files/libraries/bootstrapIcons/bootstrap-icons.woff2") != nil)
    }

    @Test
    func iconControlUsesTheBuiltInIconCatalogue() throws {
        let item = """
        <dict>
            <key>id</key><string>symbol</string>
            <key>label</key><string>Icon</string>
            <key>group</key><string>Content</string>
            <key>type</key><string>icon</string>
            <key>default</key><string>stars</string>
            <key>responsive</key><false/>
        </dict>
        """
        let manifest = manifest(withCustomItems: item)
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<span {{ component.attributes }}><i class=\"bi bi-{{ control.symbol }}\"></i>{{ control.content }}</span>"
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
        #expect(FoundryWebLibraryRegistry.uniqueRequirements(in: [package, package]) == [
            FoundryWebLibraryRegistry.iconRequirement
        ])
    }

    @Test
    func iconControlAutomaticallyIncludesItsLibraryAndRequiresAValidDefault() throws {
        let item = """
        <dict>
            <key>id</key><string>symbol</string>
            <key>label</key><string>Icon</string>
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
            $0.message == "An icon default must be a valid Foundry icon name, for example stars."
        })
    }

    @Test
    func iconControlValidatesEveryMultiControlDefault() throws {
        let item = """
        <dict>
            <key>type</key><string>icon</string>
            <key>id</key><string>icons</string>
            <key>label</key><string>Icons</string>
            <key>count</key><integer>2</integer>
            <key>subtitle</key>
            <array><string>Previous</string><string>Next</string></array>
            <key>default</key>
            <array><string>arrow-left</string><string>not-a-real-foundry-icon</string></array>
        </dict>
        """
        let manifestText = manifest(withCustomItems: item)
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let property = try #require(manifest.properties.first)
        #expect(property.defaultValue == .array([.string("arrow-left"), .string("not-a-real-foundry-icon")]))

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        #expect(diagnostics.contains {
            $0.location.hasSuffix("icons.default[1]")
                && $0.message == "An icon default must be a valid Foundry icon name, for example stars."
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
                <key>label</key><string>Title</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>text</string>
                <key>default</key><string>Hello</string>
                <key>responsive</key><false/>
            </dict>
            <dict>
                <key>type</key><string>childPicker</string>
                <key>id</key><string>content</string>
                <key>label</key><string>Content</string>
                <key>pickerItems</key><array><string>com.example.child</string></array>
                <key>accepts</key><array><string>*</string></array>
            </dict>
        </array>
        """
    }

    private func manifest(withCustomItems items: String) -> String {
        let replacement = """
        <key>customItems</key>
        <array>
            \(items)
            <dict>
                <key>type</key><string>childPicker</string>
                <key>id</key><string>content</string>
                <key>label</key><string>Content</string>
                <key>pickerItems</key><array><string>com.example.child</string></array>
                <key>accepts</key><array><string>*</string></array>
            </dict>
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

    @Test
    func componentIconCannotExceedMaximumFileSize() throws {
        let oversizedIcon = "<svg>" + String(
            repeating: " ",
            count: ComponentPackageValidator.maximumIconByteCount
        ) + "</svg>"
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<div {{ component.attributes }}>{{ control.content }}</div>",
            additionalFiles: ["icon.svg": oversizedIcon]
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

        #expect(diagnostics.contains { $0.location == "icon.svg" && $0.message.contains("64 KiB") })
    }

    @Test
    func decodedComponentIconIsSynchronouslyReusable() async throws {
        let iconURL = FileManager.default.temporaryDirectory
            .appending(path: "Foundry-Icon-Cache-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: iconURL) }
        try Data(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><rect width=\"24\" height=\"24\"/></svg>".utf8
        ).write(to: iconURL)

        #expect(ComponentIconLoader.cachedIcon(at: iconURL) == nil)
        let loaded = await ComponentIconLoader.shared.icon(at: iconURL)
        #expect(loaded != nil)
        #expect(ComponentIconLoader.cachedIcon(at: iconURL) != nil)

        await ComponentIconLoader.shared.removeIcon(at: iconURL)
        #expect(ComponentIconLoader.cachedIcon(at: iconURL) == nil)
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
        let compatibleTemplate = template.contains("{{ component.attributes }}") &&
            !template.contains("{{ component.class }}")
            ? template.replacingOccurrences(
                of: "{{ component.attributes }}",
                with: "class=\"{{ component.class }}\" {{ component.attributes }}"
            )
            : template
        let files = [
            "component.html": compatibleTemplate,
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
