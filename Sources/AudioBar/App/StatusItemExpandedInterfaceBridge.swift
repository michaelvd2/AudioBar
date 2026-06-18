import AppKit

@MainActor
final class StatusItemExpandedInterfaceBridge: NSObject {
    private weak var statusItem: NSStatusItem?
    private var session: AnyObject?
    private let onBegin: @MainActor () -> Void
    private let onEnd: @MainActor () -> Void

    init(
        statusItem: NSStatusItem,
        onBegin: @escaping @MainActor () -> Void,
        onEnd: @escaping @MainActor () -> Void
    ) {
        self.statusItem = statusItem
        self.onBegin = onBegin
        self.onEnd = onEnd
        super.init()
    }

    func installIfAvailable() {
        let setter = NSSelectorFromString("setExpandedInterfaceDelegate:")
        guard statusItem?.responds(to: setter) == true else {
            return
        }

        statusItem?.setValue(self, forKey: "expandedInterfaceDelegate")
    }

    func cancelSessionIfAvailable() {
        let cancel = NSSelectorFromString("cancel")
        if let session, session.responds(to: cancel) {
            _ = session.perform(cancel)
            return
        }

        let getter = NSSelectorFromString("expandedInterfaceSession")
        guard statusItem?.responds(to: getter) == true,
              let session = statusItem?.value(forKey: "expandedInterfaceSession") as AnyObject?,
              session.responds(to: cancel)
        else {
            return
        }

        _ = session.perform(cancel)
    }

    @objc(statusItem:didBeginExpandedInterfaceSession:)
    private func statusItem(_ statusItem: AnyObject, didBeginExpandedInterfaceSession session: AnyObject) {
        self.session = session
        onBegin()
    }

    @objc(statusItemDidEndExpandedInterfaceSession:animated:)
    private func statusItemDidEndExpandedInterfaceSession(_ statusItem: AnyObject, animated: Bool) {
        session = nil
        onEnd()
    }
}
