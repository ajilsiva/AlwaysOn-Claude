import AppKit

/// The app's entire private-API surface, isolated here. DFRFoundation has no
/// binary on disk and no .tbd in the SDK, so it cannot be linked — it must be
/// dlopen'd from the dyld shared cache. ObjC private class methods are called
/// via perform() so the package stays pure Swift. Every entry point no-ops
/// when a symbol is missing; callers check `isAvailable` and degrade to
/// menu-bar-only.
enum DFR {
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private typealias SetPresenceFn = @convention(c) (NSString, Bool) -> Void
    private typealias SetBoolFn = @convention(c) (Bool) -> Void

    private static let setPresenceFn: SetPresenceFn? = {
        guard let handle,
              let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
        else { return nil }
        return unsafeBitCast(symbol, to: SetPresenceFn.self)
    }()

    private static let showsCloseBoxFn: SetBoolFn? = {
        guard let handle,
              let symbol = dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost")
        else { return nil }
        return unsafeBitCast(symbol, to: SetBoolFn.self)
    }()

    static var isAvailable: Bool {
        setPresenceFn != nil
            && (NSTouchBarItem.self as AnyObject).responds(to: NSSelectorFromString("addSystemTrayItem:"))
    }

    static func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, _ present: Bool) {
        setPresenceFn?(identifier.rawValue as NSString, present)
    }

    static func showsCloseBoxWhenFrontMost(_ shows: Bool) {
        showsCloseBoxFn?(shows)
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        classPerform(NSTouchBarItem.self, "addSystemTrayItem:", item)
    }

    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        classPerform(NSTouchBarItem.self, "removeSystemTrayItem:", item)
    }

    static func presentSystemModal(_ bar: NSTouchBar, trayItem identifier: NSTouchBarItem.Identifier) {
        classPerform(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:",
                     bar, identifier.rawValue as NSString)
    }

    static func minimizeSystemModal(_ bar: NSTouchBar) {
        classPerform(NSTouchBar.self, "minimizeSystemModalTouchBar:", bar)
    }

    static func dismissSystemModal(_ bar: NSTouchBar) {
        classPerform(NSTouchBar.self, "dismissSystemModalTouchBar:", bar)
    }

    private static func classPerform(_ cls: AnyClass, _ selectorName: String,
                                     _ first: Any? = nil, _ second: Any? = nil) {
        let selector = NSSelectorFromString(selectorName)
        let object = cls as AnyObject
        guard object.responds(to: selector) else { return }
        if let second {
            _ = object.perform(selector, with: first, with: second)
        } else if let first {
            _ = object.perform(selector, with: first)
        } else {
            _ = object.perform(selector)
        }
    }
}
