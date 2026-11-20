import AppKit
import SwiftUI

final class TranslationScrollView: NSScrollView {
    var documentID = UUID()
    var onContentHeight: ((CGFloat, UUID) -> Void)?
    private var measurementQueued = false
    private var lastHeight: CGFloat = -1
    private var lastDocumentID: UUID?

    override func layout() {
        super.layout()
        measureContent()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        measureContent()
    }

    func measureContent() {
        guard !measurementQueued else { return }
        measurementQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementQueued = false
            guard self.window != nil,
                  let text = self.documentView as? NSTextView,
                  let layout = text.layoutManager, let container = text.textContainer,
                  container.containerSize.width > 0 else { return }
            layout.ensureLayout(for: container)
            let height = ceil(layout.usedRect(for: container).height + 2 * text.textContainerInset.height)
            guard abs(height - self.lastHeight) > 0.5 || self.lastDocumentID != self.documentID else { return }
            self.lastHeight = height
            self.lastDocumentID = self.documentID
            self.onContentHeight?(height, self.documentID)
        }
    }
}

// The document is a native, selectable text view. No custom title bar or toolbar.
struct TranslationView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var onContentHeight: (CGFloat, UUID) -> Void

    final class Coordinator {
        var documentID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TranslationScrollView {
        let scroll = TranslationScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .legacy
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 14, height: 12)
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.setAccessibilityLabel("译文")
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: TranslationScrollView, context: Context) {
        scroll.onContentHeight = onContentHeight
        scroll.documentID = model.documentID
        guard let text = scroll.documentView as? NSTextView else { return }
        let display = model.documentText
        guard text.string != display || context.coordinator.documentID != model.documentID else { return }
        let selected = text.selectedRange()
        let origin = scroll.contentView.bounds.origin
        let reset = context.coordinator.documentID != model.documentID
        context.coordinator.documentID = model.documentID

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let content = NSMutableAttributedString(string: display, attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: model.translation.isEmpty && model.error == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        if let error = model.error, let range = display.range(of: error, options: .backwards) {
            content.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(range, in: display))
        }
        text.textStorage?.setAttributedString(content)
        if reset {
            text.setSelectedRange(NSRange(location: 0, length: 0))
            scroll.contentView.scroll(to: .zero)
        } else {
            let length = (display as NSString).length
            let start = min(selected.location, length)
            text.setSelectedRange(NSRange(location: start, length: min(selected.length, length - start)))
            scroll.contentView.scroll(to: origin)
        }
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.measureContent()
    }
}
