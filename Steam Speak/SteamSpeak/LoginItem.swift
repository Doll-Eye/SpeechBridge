import Foundation
import ServiceManagement

/// Opening at login. A reader has to be there before it is thought of: the Mac restarted
/// overnight on 18 September 2026 and Steam Speak simply was not running when Big Picture
/// came up. Registered by default on first launch; the menu can turn it off.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func setEnabled(_ wanted: Bool) -> String {
        do {
            if wanted { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            log("Login item \(wanted ? "enabled" : "disabled").")
            return wanted ? "Steam Speak will open at login." : "Steam Speak will no longer open at login."
        } catch {
            log("Login item change failed: \(error.localizedDescription)")
            return "Could not change the login setting: \(error.localizedDescription)"
        }
    }

    /// Once, on first launch. Not repeated, so turning it off in the menu stays off.
    static func registerOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didSetUpLoginItem") else { return }
        defaults.set(true, forKey: "didSetUpLoginItem")
        if SMAppService.mainApp.status != .enabled {
            _ = setEnabled(true)
        }
    }
}
