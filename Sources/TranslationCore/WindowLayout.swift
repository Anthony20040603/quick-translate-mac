import Foundation
import CoreGraphics

public enum WindowLayout {
    public static let compactHeight: CGFloat = 180

    /// macOS screen coordinates increase upwards. Prefer below/right, then
    /// flip each axis independently and clamp to this display's usable area.
    public static func positionedFrame(near mouse: CGPoint, size: CGSize,
                                       visible: CGRect, gap: CGFloat = 16) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let right = mouse.x + gap
        let left = mouse.x - gap - width
        let below = mouse.y - gap - height
        let above = mouse.y + gap
        let preferredX = right + width <= visible.maxX ? right : left
        let preferredY = below >= visible.minY ? below : above
        let x = min(max(preferredX, visible.minX), visible.maxX - width)
        let y = min(max(preferredY, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Preserve the chosen width and top edge. Only automatic height is capped.
    public static func frame(current: CGRect, visible: CGRect, contentHeight: CGFloat,
                             titlebarHeight: CGFloat, newDocument: Bool) -> CGRect {
        let limit = max(1, floor(visible.height * 0.4))
        let minimum = min(compactHeight, limit)
        var height = min(limit, max(minimum, ceil(contentHeight + titlebarHeight)))
        if !newDocument { height = max(height, min(current.height, limit)) }
        let y = min(max(current.maxY - height, visible.minY), visible.maxY - height)
        return CGRect(x: current.minX, y: y, width: current.width, height: height)
    }
}
