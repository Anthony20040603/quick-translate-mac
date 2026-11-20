import Foundation

public struct HotkeyDetector {
    public enum Action: Equatable { case none, armed, triggered }
    private var firstPress: TimeInterval?
    private var cIsDown = false
    public init() {}

    public mutating func reset() {
        firstPress = nil
        cIsDown = false
    }

    public mutating func keyUp(isC: Bool) {
        if isC { cIsDown = false }
    }

    public mutating func keyDown(isC: Bool, commandOnly: Bool, isRepeat: Bool,
                                 time: TimeInterval) -> Action {
        guard commandOnly, isC else { reset(); return .none }
        guard !isRepeat, !cIsDown else { return .none }
        cIsDown = true
        if let firstPress, (0.06...0.42).contains(time - firstPress) {
            self.firstPress = nil
            return .triggered
        }
        firstPress = time
        return .armed
    }
}
