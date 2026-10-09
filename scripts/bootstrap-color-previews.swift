// Run with: swift scripts/bootstrap-color-previews.swift <bundled-bootstrap.css>
// Prints sRGB previews for AppKit colour wells. Published colours remain native
// Bootstrap CSS expressions; this cache is never the web rendering source.
import AppKit
import CryptoKit
import WebKit

@MainActor
final class PalettePreviewGenerator: NSObject, WKNavigationDelegate {
    let source: Data
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))

    init(source: Data) {
        self.source = source
        super.init()
        webView.navigationDelegate = self
    }

    func run() {
        let css = String(decoding: source, as: UTF8.self)
        webView.loadHTMLString("<html><head><style>\(css)</style></head><body></body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("""
            const properties = getComputedStyle(document.documentElement);
            const names = [...new Set(Array.from(properties).map(p => /^--bs-(.+)-500$/.exec(p)?.[1]).filter(Boolean))].sort();
            const steps = ['025','050','100','200','300','400','500','600','700','800','900','950','975'];
            const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
            const context = canvas.getContext('2d', {colorSpace:'srgb'});
            const probe = document.createElement('span'); document.body.append(probe);
            const palettes = {};
            for (const name of names) {
                palettes[name] = steps.map(step => {
                    probe.style.color = `var(--bs-${name}-${step})`;
                    context.clearRect(0,0,1,1);
                    context.fillStyle = getComputedStyle(probe).color;
                    context.fillRect(0,0,1,1);
                    return '#' + Array.from(context.getImageData(0,0,1,1).data).slice(0,3)
                        .map(v => v.toString(16).padStart(2,'0')).join('').toUpperCase();
                });
            }
            JSON.stringify(palettes);
            """) { result, error in
                guard error == nil, let json = result as? String,
                      let data = json.data(using: .utf8),
                      let palettes = try? JSONSerialization.jsonObject(with: data) else {
                    fputs("Bootstrap preview generation failed: \(String(describing: error))\n", stderr)
                    exit(1)
                }
                let checksum = SHA256.hash(data: self.source).map { String(format: "%02x", $0) }.joined()
                let output = try! JSONSerialization.data(withJSONObject: ["cssSHA256": checksum, "palettes": palettes], options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: output, as: UTF8.self))
                exit(0)
            }
    }
}

guard CommandLine.arguments.count == 2 else { fatalError("Supply the bundled Bootstrap CSS path") }
_ = NSApplication.shared
let generator = try MainActor.assumeIsolated {
    let generator = PalettePreviewGenerator(source: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    generator.run()
    return generator
}
RunLoop.main.run()
