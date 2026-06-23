import Foundation

public enum PopoverClickResolution: Equatable, Sendable {
    case open
    case close
    case ignore
}

/// Collapses the multiple handlers that fire for a single status-item click
/// into exactly one toggle.
///
/// A status-item click is observed by two independent paths: the button action
/// and the OS expanded-interface session (`onBegin`/`onEnd`). They fire around
/// the same mouse-down in a non-deterministic order. Without coalescing they
/// race on shared open/close intent — when the OS session opens first, the
/// button action reads "open" and immediately closes the popover it just
/// opened, producing the intermittent "won't open on click".
///
/// The first handler inside a fresh window makes the open/close decision; every
/// other handler belonging to the same physical click resolves to `.ignore`.
public struct PopoverClickCoalescer: Sendable {
    public let window: TimeInterval

    public init(window: TimeInterval) {
        self.window = window
    }

    public func resolve(
        intendedOpen: Bool,
        lastInteraction: Date?,
        now: Date
    ) -> PopoverClickResolution {
        if let lastInteraction, now.timeIntervalSince(lastInteraction) < window {
            return .ignore
        }
        return intendedOpen ? .close : .open
    }
}
