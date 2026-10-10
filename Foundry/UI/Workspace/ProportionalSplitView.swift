import AppKit
import SwiftUI

struct ProportionalSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    @Binding var leadingRatio: Double
    let minimumLeadingWidth: CGFloat
    let minimumTrailingWidth: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    init(
        leadingRatio: Binding<Double>,
        minimumLeadingWidth: CGFloat,
        minimumTrailingWidth: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _leadingRatio = leadingRatio
        self.minimumLeadingWidth = minimumLeadingWidth
        self.minimumTrailingWidth = minimumTrailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(leadingRatio: $leadingRatio)
    }

    func makeNSView(context: Context) -> RatioSplitView {
        let splitView = RatioSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        splitView.minimumLeadingWidth = minimumLeadingWidth
        splitView.minimumTrailingWidth = minimumTrailingWidth
        splitView.preferredLeadingRatio = normalized(leadingRatio)

        let leadingView = NSHostingView(rootView: leading)
        let trailingView = NSHostingView(rootView: trailing)
        configureHostingView(leadingView)
        configureHostingView(trailingView)
        splitView.addArrangedSubview(leadingView)
        splitView.addArrangedSubview(trailingView)
        context.coordinator.leadingView = leadingView
        context.coordinator.trailingView = trailingView
        return splitView
    }

    func updateNSView(_ splitView: RatioSplitView, context: Context) {
        context.coordinator.leadingRatio = $leadingRatio
        context.coordinator.leadingView?.rootView = leading
        context.coordinator.trailingView?.rootView = trailing
        splitView.minimumLeadingWidth = minimumLeadingWidth
        splitView.minimumTrailingWidth = minimumTrailingWidth
        let ratio = normalized(leadingRatio)
        if abs(splitView.preferredLeadingRatio - ratio) > 0.0001 {
            splitView.preferredLeadingRatio = ratio
            splitView.needsLayout = true
        }
    }

    static func dismantleNSView(_ splitView: RatioSplitView, coordinator: Coordinator) {
        splitView.delegate = nil
    }

    private func configureHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func normalized(_ value: Double) -> CGFloat {
        CGFloat(value.clamped(to: 0.05...0.95))
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var leadingRatio: Binding<Double>
        var leadingView: NSHostingView<Leading>?
        var trailingView: NSHostingView<Trailing>?

        init(leadingRatio: Binding<Double>) {
            self.leadingRatio = leadingRatio
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            guard let splitView = splitView as? RatioSplitView else {
                return proposedMinimumPosition
            }
            return max(proposedMinimumPosition, splitView.minimumLeadingWidth)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            guard let splitView = splitView as? RatioSplitView else {
                return proposedMaximumPosition
            }
            return min(
                proposedMaximumPosition,
                splitView.bounds.width - splitView.minimumTrailingWidth - splitView.dividerThickness
            )
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? RatioSplitView,
                  !splitView.isApplyingPreferredRatio else {
                return
            }
            let availableWidth = splitView.bounds.width - splitView.dividerThickness
            guard availableWidth > 0, let leadingView else { return }
            let ratio = Double((leadingView.frame.width / availableWidth).clamped(to: 0.05...0.95))
            splitView.preferredLeadingRatio = CGFloat(ratio)
            if abs(leadingRatio.wrappedValue - ratio) > 0.0001 {
                leadingRatio.wrappedValue = ratio
            }
        }
    }
}

final class RatioSplitView: NSSplitView {
    var preferredLeadingRatio: CGFloat = 0.3
    var minimumLeadingWidth: CGFloat = 160
    var minimumTrailingWidth: CGFloat = 300
    fileprivate var isApplyingPreferredRatio = false

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        applyPreferredRatio()
    }

    override func layout() {
        super.layout()
        applyPreferredRatio()
    }

    private func applyPreferredRatio() {
        guard subviews.count == 2, bounds.width > 0, !isApplyingPreferredRatio else { return }
        let availableWidth = max(0, bounds.width - dividerThickness)
        let maximumLeadingWidth = max(minimumLeadingWidth, availableWidth - minimumTrailingWidth)
        let leadingWidth = (availableWidth * preferredLeadingRatio)
            .clamped(to: minimumLeadingWidth...maximumLeadingWidth)
        guard abs(subviews[0].frame.width - leadingWidth) > 0.5 else { return }
        isApplyingPreferredRatio = true
        setPosition(leadingWidth, ofDividerAt: 0)
        isApplyingPreferredRatio = false
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
