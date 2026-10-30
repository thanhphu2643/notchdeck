import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        // Above the menu bar so the panel can cover the notch area.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

extension NSScreen {
    /// Size of the camera housing, or nil on screens without one.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea
        else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }

    /// Size used for the collapsed island: the real notch, or a fake one hugging the menu bar.
    var islandSize: CGSize {
        notchSize ?? CGSize(width: 200, height: max(frame.maxY - visibleFrame.maxY, 24))
    }
}

/// Owns the panel and decides when it expands, by polling the cursor position.
/// Polling avoids needing Accessibility permission for global event monitors
/// and also works mid-drag, which is how files get dropped on the shelf.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    let model: NotchModel
    private var screen: NSScreen
    private var leftAt: Date?
    private var menuOpen = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        screen = Self.preferredScreen()
        model = NotchModel(notchSize: screen.islandSize)

        let host = NSHostingView(rootView: NotchView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackCursor() }
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.screenChanged() }
            }
            .store(in: &cancellables)
        model.$isExpanded
            .sink { [weak self] expanded in self?.panel.ignoresMouseEvents = !expanded }
            .store(in: &cancellables)
        // Menus (e.g. settings) open outside the island; stay expanded while one is up.
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.menuOpen = true } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.menuOpen = false } }
            .store(in: &cancellables)
    }

    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenChanged() {
        screen = Self.preferredScreen()
        model.notchSize = screen.islandSize
        layout()
    }

    private func layout() {
        let size = model.expandedSize
        let width = size.width + 40, height = size.height + 30 // room for the shadow
        panel.setFrame(
            NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height),
            display: true
        )
    }

    /// Screen-space rect of the island at a given size, anchored to the top center.
    private func rect(for size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    private func trackCursor() {
        let mouse = NSEvent.mouseLocation
        if model.isExpanded {
            if menuOpen || rect(for: model.expandedSize).insetBy(dx: -12, dy: -12).contains(mouse) {
                leftAt = nil
            } else if let leftAt {
                if Date().timeIntervalSince(leftAt) > 0.25 { collapse() }
            } else {
                leftAt = Date()
            }
        } else if rect(for: model.collapsedSize).insetBy(dx: -6, dy: -2).contains(mouse) {
            leftAt = nil
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { model.setExpanded(true) }
        }
    }

    private func collapse() {
        leftAt = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { model.setExpanded(false) }
    }
}
