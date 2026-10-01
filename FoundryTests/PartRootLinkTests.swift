import Testing
@testable import Foundry

struct PartRootLinkTests {
    let anchor = #"<a data-foundry-root-link="link" href="/next" target="_blank" rel="noopener noreferrer" aria-label="Next"></a>"#

    @Test
    func conversionPreservesContentAttributesAndChosenPosition() {
        for position in ["static", "relative", "absolute", "fixed", "sticky"] {
            let original = "<!-- > --><section class='card' id='card' style='display:grid;position:\(position)' title='a > b'><div><img src='photo.jpg' alt='Photo'></div></section><!-- end -->"
            let converted = PartRootLinkRenderer.convert(original, anchor: anchor)
            #expect(converted.hasPrefix("<!-- > --><a "))
            #expect(converted.hasSuffix("</a><!-- end -->"))
            #expect(converted.contains("style='display:grid;position:\(position)'"))
            #expect(converted.contains("title='a > b'"))
            #expect(converted.contains("<div><img src='photo.jpg' alt='Photo'></div>"))
            #expect(converted.contains("data-foundry-link-display=\"block\""))
        }
    }

    @Test
    func interactiveChildrenLeaveRootIntactWithDiagnostic() {
        for child in ["<a href='/inner'>Inner</a>", "<button>Save</button>", "<span tabindex='0'>Focus</span>", "<video controls></video>"] {
            let output = PartRootLinkRenderer.convert("<div>\(child)</div>", anchor: anchor)
            #expect(output.hasPrefix("<div"))
            #expect(output.contains("data-foundry-link-error"))
            #expect(output.contains(child))
            #expect(!output.contains("data-foundry-root-link"))
        }
    }

    @Test
    func unsupportedRootsRemainUntouchedAndInlineRootsStayInline() {
        for html in ["<img src='x'>", "<video src='x'></video>", "<button>Save</button>", "<table><tr><td>Cell</td></tr></table>"] {
            #expect(PartRootLinkRenderer.convert(html, anchor: anchor) == html)
        }
        let output = PartRootLinkRenderer.convert("<span>Hello</span>", anchor: anchor)
        #expect(output.contains("data-foundry-link-display=\"inline\""))
        #expect(output.hasSuffix("Hello</a>"))
    }
}
