import Foundation

enum SiteCodeSection: Int, CaseIterable, Identifiable {
    case head, bodyStart, bodyEnd, css, javaScript

    var id: Self { self }

    var title: String {
        switch self {
        case .head: "Head"
        case .bodyStart: "Body Start"
        case .bodyEnd: "Body End"
        case .css: "CSS"
        case .javaScript: "JavaScript"
        }
    }

    var language: SourceCodeLanguage {
        switch self {
        case .css: .css
        case .javaScript: .javaScript
        default: .html
        }
    }

    var subtitle: String {
        switch self {
        case .head: "Inside <head> on every page. Include <style> or <script> tags where needed."
        case .bodyStart: "Immediately after the opening <body> tag on every page."
        case .bodyEnd: "Before </body>, after Foundry’s part scripts."
        case .css: "Site-wide styles, loaded after generated styles. No <style> tags needed."
        case .javaScript: "Site-wide JavaScript module, loaded after page scripts in preview and export. No <script> tags needed."
        }
    }
}
