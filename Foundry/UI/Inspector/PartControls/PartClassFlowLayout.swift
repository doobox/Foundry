import SwiftUI

/// Places class tokens on new lines as the Inspector narrows or the list grows.
struct PartClassFlowLayout: Layout {
    let spacing: CGFloat
    var minimumLineCount = 1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 240)
        let result = positions(for: subviews, width: width)
        let textLineHeight = result.sizes.last?.height ?? 0
        let minimumHeight = textLineHeight * CGFloat(minimumLineCount)
        return CGSize(width: width, height: max(result.height, minimumHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = positions(for: subviews, width: max(1, bounds.width))
        for (index, subview) in subviews.enumerated() {
            let size = result.sizes[index]
            subview.place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func positions(for subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], sizes: [CGSize], height: CGFloat) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let measured = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(measured.width, width), height: measured.height)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, sizes, y + rowHeight)
    }
}
