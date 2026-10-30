import ServiceManagement
import SwiftUI

/// Registers the app as a login item via SMAppService (macOS 13+).
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            NSLog("NotchDeck: launch at login failed: \(error)")
        }
        // The user may have to allow it in System Settings › Login Items.
        if enabled && service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        isEnabled = service.status == .enabled
    }
}
